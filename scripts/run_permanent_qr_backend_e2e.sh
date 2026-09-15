#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-supabase_db_AlphaPos}"
WEB_CONFIG="${WEB_CONFIG:-/opt/alphapos/customer-order-web/config.js}"
MERCHANT_ID="${MERCHANT_ID:-163350b0-056d-4d5e-b5d4-24e7aac5ab6d}"
BRANCH_ID="${BRANCH_ID:-5037e6ed-03da-4d4c-9777-68ad37899331}"
TABLE_NUMBER="${TABLE_NUMBER:-1}"
API_URL="${API_URL:-https://api.alphaposweb.com/functions/v1/issue-customer-session-token}"

psql_cmd() { docker exec "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -Atc "$1"; }
anon_key="$(awk -F"'" '/supabaseKey:/{print $2; exit}' "$WEB_CONFIG")"
permanent_key="$(psql_cmd "select qr_code_identifier from public.restaurant_tables where merchant_id='${MERCHANT_ID}' and table_number='${TABLE_NUMBER}' and is_deleted=false limit 1")"

test -n "$anon_key"
test -n "$permanent_key"
test "$(psql_cmd "select count(*) from public.table_sessions where merchant_id='${MERCHANT_ID}' and table_number='${TABLE_NUMBER}' and is_active=1")" = "0"

request_id=""
service_id=""
session_id=""
cleanup() {
  if [[ -n "$service_id" ]]; then psql_cmd "delete from public.service_requests where id='${service_id}'" >/dev/null || true; fi
  if [[ -n "$session_id" ]]; then psql_cmd "delete from public.table_sessions where id='${session_id}'" >/dev/null || true; fi
}
trap cleanup EXIT

initial="$(curl -fsS -X POST "$API_URL" -H 'Content-Type: application/json' -H "apikey: ${anon_key}" -H "Authorization: Bearer ${anon_key}" --data "{\"merchant_id\":\"${MERCHANT_ID}\",\"table_number\":\"${TABLE_NUMBER}\",\"permanent_key\":\"${permanent_key}\"}")"
request_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("approval_request_id", ""))' "$initial")"
test -n "$request_id"
service_id="$(psql_cmd "select service_request_id from public.permanent_qr_access_requests where id='${request_id}'")"
test -n "$service_id"
echo "initial=pending"

psql_cmd "update public.service_requests set status='completed' where id='${service_id}'" >/dev/null
session_id="$(psql_cmd "select table_session_id from public.permanent_qr_access_requests where id='${request_id}' and status='approved'")"
test -n "$session_id"

approved="$(curl -fsS -X POST "$API_URL" -H 'Content-Type: application/json' -H "apikey: ${anon_key}" -H "Authorization: Bearer ${anon_key}" --data "{\"merchant_id\":\"${MERCHANT_ID}\",\"table_number\":\"${TABLE_NUMBER}\",\"permanent_key\":\"${permanent_key}\",\"approval_request_id\":\"${request_id}\"}")"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d.get("access_token") and d.get("session_token") and d.get("branch_id"); print("approval=jwt_issued")' "$approved"
jwt="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["access_token"])' "$approved")"
menu_count="$(curl -fsS "https://api.alphaposweb.com/rest/v1/menu_items?select=id&is_deleted=eq.false&is_available=eq.true&or=(branch_id.is.null,branch_id.eq.${BRANCH_ID})&merchant_id=eq.${MERCHANT_ID}" -H "apikey: ${anon_key}" -H "Authorization: Bearer ${jwt}" -H 'Prefer: count=exact' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
test "$menu_count" -gt 0
echo "menu=available"
echo "permanent QR backend e2e passed"
