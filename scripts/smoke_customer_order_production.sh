#!/usr/bin/env bash
set -euo pipefail

# Production smoke for the Cloudflare -> customer JWT -> PostgREST RPC path.
# It creates one isolated, staff-unconfirmed web order, replays the identical
# request, proves that exactly one row exists, and removes all smoke data.

WEB_URL="${WEB_URL:-https://sync.alphaposweb.com}"
API_URL="${API_URL:-https://api.alphaposweb.com}"
VPS_HOST="${VPS_HOST:-root@119.59.99.163}"
VPS_SSH_KEY="${VPS_SSH_KEY:-$HOME/.ssh/id_alphapos}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_AlphaPos}"
MERCHANT_ID="${MERCHANT_ID:-163350b0-056d-4d5e-b5d4-24e7aac5ab6d}"
BRANCH_ID="${BRANCH_ID:-5037e6ed-03da-4d4c-9777-68ad37899331}"

if [[ "${ALLOW_PRODUCTION_SMOKE:-}" != "yes" ]]; then
  echo "Refusing to touch production. Re-run with ALLOW_PRODUCTION_SMOKE=yes after confirming the target URLs and IDs." >&2
  exit 64
fi
[[ "$WEB_URL" == https://* && "$API_URL" == https://* ]] || { echo "Production smoke requires HTTPS endpoints." >&2; exit 64; }

uuid() { uuidgen | tr '[:upper:]' '[:lower:]'; }
SESSION_ID="$(uuid)"
SESSION_TOKEN="$(uuid)"
ORDER_ID="$(uuid)"
ITEM_ROW_ID="$(uuid)"
IDEMPOTENCY_KEY="$(uuid)"
TABLE_NUMBER="S-${SESSION_ID:0:8}"

db() {
  ssh -i "$VPS_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$VPS_HOST" \
    "docker exec $DB_CONTAINER psql -v ON_ERROR_STOP=1 -U postgres -d postgres -At -c \"$1\""
}

cleanup() {
  db "
BEGIN;
DELETE FROM public.sync_outbox WHERE idempotency_key='customer-order:$ORDER_ID' OR payload->>'order_id'='$ORDER_ID';
DELETE FROM public.customer_order_operations WHERE table_session_id='$SESSION_ID';
DELETE FROM public.orders WHERE id='$ORDER_ID';
DELETE FROM public.table_sessions WHERE id='$SESSION_ID';
COMMIT;
" >/dev/null || true
}
trap cleanup EXIT INT TERM

echo "stage=cloudflare_assets"
HTML="$(curl --max-time 20 --fail-with-body -sS "$WEB_URL/?smoke=$SESSION_ID")"
APP_PATH="$(sed -n 's/.*<script[^>]*src="\([^"]*\.js[^\"]*\)"[^>]*><\/script>.*/\1/p' <<<"$HTML" | tail -1)"
test -n "$APP_PATH"
APP_JS="$(curl --max-time 20 --fail-with-body -sS "$WEB_URL/${APP_PATH#/}")"
grep -q "orderSubmitUncertain" <<<"$APP_JS"
CONFIG_JS="$(curl --max-time 20 --fail-with-body -sS "$WEB_URL/config.js")"
ANON_KEY="$(sed -n 's/.*"supabaseKey":"\([^"]*\)".*/\1/p' <<<"$CONFIG_JS")"
if [[ -z "$ANON_KEY" ]]; then
  ANON_KEY="$(sed -n "s/.*supabaseKey: '\([^']*\)'.*/\1/p" <<<"$CONFIG_JS")"
fi
test -n "$ANON_KEY"

echo "stage=database_fixture"
IFS='|' read -r MENU_ID MENU_PRICE < <(db "
SELECT id,price FROM public.menu_items
WHERE merchant_id='$MERCHANT_ID' AND COALESCE(is_available,true) AND NOT COALESCE(is_deleted,false)
ORDER BY id LIMIT 1;
")
test -n "$MENU_ID"

db "
INSERT INTO public.table_sessions(id,merchant_id,branch_id,table_number,session_token,is_active,guest_count,created_at)
VALUES('$SESSION_ID','$MERCHANT_ID','$BRANCH_ID','$TABLE_NUMBER','$SESSION_TOKEN',1,1,now());
" >/dev/null

echo "stage=customer_session_exchange"
TOKEN_RESPONSE="$(curl --max-time 20 --fail-with-body -sS "$API_URL/functions/v1/issue-customer-session-token" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H 'Content-Type: application/json' \
  --data "{\"table_number\":\"$TABLE_NUMBER\",\"session_token\":\"$SESSION_TOKEN\"}")"
CUSTOMER_JWT="$(jq -er '.access_token' <<<"$TOKEN_RESPONSE")"
test "$(jq -r '.branch_id' <<<"$TOKEN_RESPONSE")" = "$BRANCH_ID"

PAYLOAD="$(jq -nc --arg oid "$ORDER_ID" --arg iid "$ITEM_ROW_ID" --arg menu "$MENU_ID" \
  --arg price "$MENU_PRICE" --arg key "$IDEMPOTENCY_KEY" \
  '{p_order:{id:$oid,order_number:("SMOKE-"+($oid[0:8])),guest_count:1,discount:0,idempotency_key:$key},p_items:[{id:$iid,item_id:$menu,quantity:1,price:($price|tonumber),notes:"automated production smoke; do not prepare"}],p_modifiers:[]}' )"

submit() {
  curl --max-time 20 --fail-with-body -sS "$API_URL/rest/v1/rpc/create_customer_order" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CUSTOMER_JWT" -H 'Content-Type: application/json' \
    --data "$PAYLOAD"
}

echo "stage=idempotent_submission"
FIRST="$(submit)"
SECOND="$(submit)"
test "${FIRST//\"/}" = "$ORDER_ID"
test "$SECOND" = "$FIRST"

COUNTS="$(db "
SELECT count(*),(SELECT count(*) FROM public.order_items WHERE order_id='$ORDER_ID')
FROM public.orders WHERE id='$ORDER_ID' AND order_source='web' AND is_staff_confirmed=false;
")"
test "$COUNTS" = "1|1"
echo "verified=cloudflare_asset,customer_session,rpc_submission,idempotent_replay database_counts=$COUNTS"
echo "production customer-order smoke passed; cleanup will now remove the isolated order and session"
