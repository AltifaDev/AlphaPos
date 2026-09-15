#!/usr/bin/env bash
set -euo pipefail

API_URL="${API_URL:-https://api.alphaposweb.com}"
WEB_URL="${WEB_URL:-https://sync.alphaposweb.com}"
VPS_HOST="${VPS_HOST:-root@119.59.99.163}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_AlphaPos}"
MERCHANT_ID="${MERCHANT_ID:-163350b0-056d-4d5e-b5d4-24e7aac5ab6d}"
BRANCH_ID="${BRANCH_ID:-5037e6ed-03da-4d4c-9777-68ad37899331}"

SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
TABLE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
SESSION_TOKEN=$(uuidgen)
ORDER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
OTHER_ORDER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
ITEM_ROW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
IDEMPOTENCY_KEY=$(uuidgen | tr '[:upper:]' '[:lower:]')
TABLE_NUMBER="CWE2E${SESSION_ID:0:5}"

cleanup() {
  ssh "$VPS_HOST" "docker exec -i $DB_CONTAINER psql -v ON_ERROR_STOP=1 -U postgres -d postgres" <<SQL >/dev/null
DELETE FROM public.sync_outbox WHERE idempotency_key IN ('customer-order:$ORDER_ID') OR payload->>'session_id'='$SESSION_ID';
DELETE FROM public.sync_outbox WHERE payload->>'table_session_id'='$SESSION_ID';
DELETE FROM public.sync_outbox WHERE payload->>'request_id' IN (SELECT id::text FROM public.service_requests WHERE merchant_id='$MERCHANT_ID' AND branch_id='$BRANCH_ID' AND table_number='$TABLE_NUMBER');
DELETE FROM public.customer_order_operations WHERE table_session_id='$SESSION_ID';
DELETE FROM public.service_requests WHERE merchant_id='$MERCHANT_ID' AND branch_id='$BRANCH_ID' AND table_number='$TABLE_NUMBER';
DELETE FROM public.orders WHERE id='$ORDER_ID';
DELETE FROM public.orders WHERE id='$OTHER_ORDER_ID';
DELETE FROM public.table_sessions WHERE id='$SESSION_ID';
DELETE FROM public.restaurant_tables WHERE id='$TABLE_ID';
SQL
}
trap cleanup EXIT

read -r MENU_ID MENU_PRICE < <(
  ssh "$VPS_HOST" "docker exec $DB_CONTAINER psql -U postgres -d postgres -AtF ' ' -c \"SELECT id,price FROM public.menu_items WHERE merchant_id='$MERCHANT_ID' AND COALESCE(is_available,true) AND NOT COALESCE(is_deleted,false) ORDER BY id LIMIT 1\""
)
test -n "$MENU_ID"

DINING_AREA_ID=$(ssh "$VPS_HOST" "docker exec $DB_CONTAINER psql -U postgres -d postgres -Atc \"SELECT id FROM public.dining_areas WHERE merchant_id='$MERCHANT_ID' AND branch_id='$BRANCH_ID' AND is_active AND NOT is_deleted ORDER BY sort_order,floor_number LIMIT 1\"")
test -n "$DINING_AREA_ID"

ssh "$VPS_HOST" "docker exec -i $DB_CONTAINER psql -v ON_ERROR_STOP=1 -U postgres -d postgres" <<SQL >/dev/null
INSERT INTO public.restaurant_tables(id,merchant_id,branch_id,dining_area_id,table_number,capacity,status,floor)
VALUES('$TABLE_ID','$MERCHANT_ID','$BRANCH_ID','$DINING_AREA_ID','$TABLE_NUMBER',2,'occupied',1);
INSERT INTO public.table_sessions(id,merchant_id,branch_id,table_id,table_number,session_token,is_active,guest_count,created_at)
VALUES('$SESSION_ID','$MERCHANT_ID','$BRANCH_ID','$TABLE_ID','$TABLE_NUMBER','$SESSION_TOKEN',1,2,now());
SQL

ANON_KEY=$(curl -fsS "$WEB_URL/config.js" \
  | sed 's/^window\.ALPHAPOS_CONFIG = //' \
  | sed 's/;[[:space:]]*$//' \
  | jq -r '.supabaseKey // empty')
test -n "$ANON_KEY"

printf 'stage=customer_token\n'
TOKEN_RESPONSE=$(curl --fail-with-body -sS "$API_URL/functions/v1/issue-customer-session-token" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H 'Content-Type: application/json' \
  --data "{\"table_number\":\"$TABLE_NUMBER\",\"session_token\":\"$SESSION_TOKEN\"}")
CUSTOMER_JWT=$(jq -r '.access_token' <<<"$TOKEN_RESPONSE")
test "$CUSTOMER_JWT" != null
test "$(jq -r '.branch_id' <<<"$TOKEN_RESPONSE")" = "$BRANCH_ID"

MENU_ROWS=$(curl -fsS "$API_URL/rest/v1/menu_items?id=eq.$MENU_ID&select=id" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT")
test "$(jq 'length' <<<"$MENU_ROWS")" = "1"
SESSION_ROWS=$(curl -fsS "$API_URL/rest/v1/table_sessions?id=eq.$SESSION_ID&select=id" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT")
test "$(jq 'length' <<<"$SESSION_ROWS")" = "1"

ORDER_PAYLOAD=$(jq -nc \
  --arg oid "$ORDER_ID" --arg iid "$ITEM_ROW_ID" --arg menu "$MENU_ID" --arg price "$MENU_PRICE" --arg ikey "$IDEMPOTENCY_KEY" \
  '{p_order:{id:$oid,order_number:("WEB-E2E-"+($oid[0:8])),guest_count:2,discount:0,idempotency_key:$ikey},p_items:[{id:$iid,item_id:$menu,quantity:1,price:($price|tonumber),notes:"e2e"}],p_modifiers:[]}')

rpc() {
  curl -sS "$API_URL/rest/v1/rpc/create_customer_order" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT" -H 'Content-Type: application/json' \
    --data "$ORDER_PAYLOAD"
}

printf 'stage=create_order\n'
FIRST=$(rpc)
if [[ "$FIRST" == \{* ]]; then jq '{code,message,details,hint}' <<<"$FIRST"; exit 1; fi
SECOND=$(rpc)
test "${FIRST//\"/}" = "$ORDER_ID"
test "$SECOND" = "$FIRST"

printf 'stage=canonical_order_bundle\n'
BUNDLE=$(curl --fail-with-body -sS "$API_URL/rest/v1/rpc/get_table_order_bundle" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT" -H 'Content-Type: application/json' \
  --data "{\"p_table_session_id\":\"$SESSION_ID\",\"p_branch_id\":\"$BRANCH_ID\"}")
test "$(jq -r '.contract_version' <<<"$BUNDLE")" = "1"
test "$(jq -r '.table_session.id' <<<"$BUNDLE")" = "$SESSION_ID"
test "$(jq -r '.orders | length' <<<"$BUNDLE")" = "1"
test "$(jq -r '.orders[0].order_items | length' <<<"$BUNDLE")" = "1"
test "$(jq -r '.revision > 1' <<<"$BUNDLE")" = "true"

CONFLICT_PAYLOAD=$(jq '.p_items[0].quantity=2' <<<"$ORDER_PAYLOAD")
CONFLICT=$(curl -sS "$API_URL/rest/v1/rpc/create_customer_order" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT" -H 'Content-Type: application/json' \
  --data "$CONFLICT_PAYLOAD")
printf 'conflict_message=%s\n' "$(jq -r '.message // .code // "unknown"' <<<"$CONFLICT")"
test "$(jq -r '.message' <<<"$CONFLICT")" = "idempotency_conflict"

ANON_DENIED_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' "$API_URL/rest/v1/rpc/create_customer_order" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H 'Content-Type: application/json' \
  --data "$ORDER_PAYLOAD")
printf 'anon_denied_status=%s\n' "$ANON_DENIED_STATUS"
[[ "$ANON_DENIED_STATUS" =~ ^(401|403|404)$ ]]

REQUEST_KEY=$(uuidgen | tr '[:upper:]' '[:lower:]')
printf 'stage=service_request\n'
REQUEST_RESULT=$(curl -sS "$API_URL/rest/v1/rpc/create_customer_service_request" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT" -H 'Content-Type: application/json' \
  --data "{\"p_request_type\":\"General Help\",\"p_idempotency_key\":\"$REQUEST_KEY\"}")
if [[ "$REQUEST_RESULT" == \{* ]] && [[ "$(jq -r '.code // empty' <<<"$REQUEST_RESULT")" != "" ]]; then
  jq '{code,message,details,hint}' <<<"$REQUEST_RESULT"
  exit 1
fi
test -n "$REQUEST_RESULT"

COUNTS=$(ssh "$VPS_HOST" "docker exec $DB_CONTAINER psql -U postgres -d postgres -AtF ' ' -c \"SELECT (SELECT count(*) FROM orders WHERE id='$ORDER_ID'),(SELECT count(*) FROM order_items WHERE order_id='$ORDER_ID'),(SELECT count(*) FROM customer_order_operations WHERE table_session_id='$SESSION_ID'),(SELECT count(*) FROM service_requests WHERE table_number='$TABLE_NUMBER'),(SELECT count(*) FROM sync_outbox WHERE payload->>'session_id'='$SESSION_ID'),(SELECT count(*) FROM sync_outbox WHERE job_type='order_bundle.changed' AND payload->>'table_session_id'='$SESSION_ID')\"")
printf 'observed_counts=%s\n' "$COUNTS"
read -r ORDER_COUNT ITEM_COUNT OP_COUNT REQUEST_COUNT SESSION_OUTBOX_COUNT BUNDLE_OUTBOX_COUNT <<<"$COUNTS"
test "$ORDER_COUNT $ITEM_COUNT $OP_COUNT $REQUEST_COUNT" = "1 1 1 1"
test "$SESSION_OUTBOX_COUNT" -ge 1
test "$BUNDLE_OUTBOX_COUNT" -ge 1

OTHER_BRANCH_ID=$(ssh "$VPS_HOST" "docker exec $DB_CONTAINER psql -U postgres -d postgres -Atc \"SELECT id FROM branches WHERE merchant_id='$MERCHANT_ID' AND id<>'$BRANCH_ID' ORDER BY id LIMIT 1\"")
if [[ -n "$OTHER_BRANCH_ID" ]]; then
  ssh "$VPS_HOST" "docker exec -i $DB_CONTAINER psql -v ON_ERROR_STOP=1 -U postgres -d postgres" <<SQL >/dev/null
INSERT INTO public.orders(id,merchant_id,branch_id,order_number,table_number,total,status,created_at)
VALUES('$OTHER_ORDER_ID','$MERCHANT_ID','$OTHER_BRANCH_ID','BR-E2E-${OTHER_ORDER_ID:0:8}','QUICK',1,'pending',now());
SQL
  CROSS_BRANCH=$(curl -fsS "$API_URL/rest/v1/orders?id=eq.$OTHER_ORDER_ID&select=id" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT")
  printf 'cross_branch_rows=%s\n' "$CROSS_BRANCH"
  test "$CROSS_BRANCH" = "[]"
fi

ssh "$VPS_HOST" "docker exec $DB_CONTAINER psql -U postgres -d postgres -c \"UPDATE orders SET status='completed' WHERE id='$ORDER_ID'; UPDATE table_sessions SET is_active=0,ended_at=now() WHERE id='$SESSION_ID';\"" >/dev/null
CLOSED_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' "$API_URL/functions/v1/issue-customer-session-token" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H 'Content-Type: application/json' \
  --data "{\"table_number\":\"$TABLE_NUMBER\",\"session_token\":\"$SESSION_TOKEN\"}")
test "$CLOSED_STATUS" = "401"

printf 'customer_session_branch=%s\n' "$BRANCH_ID"
printf 'transaction_counts=%s\n' "$COUNTS"
printf 'idempotency_conflict=blocked anon_rpc=blocked cross_branch=hidden closed_session=blocked\n'
printf 'customer web backend e2e passed\n'
