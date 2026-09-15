#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d'
branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
other_branch='b51c39d7-2eac-49ce-b1db-8d5cb3b4b3ef'
vps='root@119.59.99.163'
anon_key=$(plutil -extract SUPABASE_ANON_KEY raw AlphaPosStaff/AlphaPosStaff/Config.plist)

pair_json=$(ssh "$vps" "docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres -v ON_ERROR_STOP=1 -qAt" <<SQL
WITH generated AS (
  SELECT gen_random_uuid() id, replace(gen_random_uuid()::text || '-' || gen_random_uuid()::text, '-', '') token
), inserted AS (
  INSERT INTO public.device_pairing_tokens(id,merchant_id,branch_id,token,pairing_code,expires_at,is_used,created_at)
  SELECT id,'$merchant_id'::uuid,'$branch_id'::uuid,token,lpad((floor(random()*1000000))::int::text,6,'0'),now()+interval '10 minutes',false,now()
  FROM generated RETURNING id,token
)
SELECT json_build_object('token',token,'pairing_id',id)::text FROM inserted;
SQL
)
pair_token=$(printf '%s' "$pair_json" | jq -r '.token')
pairing_id=$(printf '%s' "$pair_json" | jq -r '.pairing_id')

auth_response=$(curl -fsS https://api.alphaposweb.com/functions/v1/issue-merchant-token \
  -H "apikey: $anon_key" -H "Authorization: Bearer $anon_key" -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg token "$pair_token" '{pairing_token:$token,device_name:"Codex E2E iPhone",device_fingerprint_hash:"codex-e2e-20260811"}')")
access_token=$(printf '%s' "$auth_response" | jq -r '.access_token')
refresh_token=$(printf '%s' "$auth_response" | jq -r '.refresh_token')
device_id=$(printf '%s' "$auth_response" | jq -r '.device_id')

decode_branch() {
  printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+' | awk '{l=length($0)%4;if(l==2)$0=$0"==";else if(l==3)$0=$0"=";print}' \
    | base64 -d 2>/dev/null | jq -r '.branch_id'
}
claimed_branch=$(decode_branch "$access_token")
test "$claimed_branch" = "$branch_id"

refresh_response=$(curl -fsS https://api.alphaposweb.com/functions/v1/refresh-token \
  -H "apikey: $anon_key" -H "Authorization: Bearer $anon_key" -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg device "$device_id" --arg refresh "$refresh_token" '{device_id:$device,refresh_token:$refresh}')")
refreshed_token=$(printf '%s' "$refresh_response" | jq -r '.access_token')
refreshed_branch=$(decode_branch "$refreshed_token")
test "$refreshed_branch" = "$branch_id"

menu_json=$(ssh "$vps" "docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres -At" <<SQL
SELECT json_build_object('id',id,'name',name,'price',price)::text FROM public.menu_items
WHERE merchant_id='$merchant_id'::uuid AND COALESCE(is_deleted,false)=false AND COALESCE(is_available,true)=true
ORDER BY created_at LIMIT 1;
SQL
)
item_id=$(printf '%s' "$menu_json" | jq -r '.id')
item_name=$(printf '%s' "$menu_json" | jq -r '.name')
item_price=$(printf '%s' "$menu_json" | jq -r '.price')

order_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
order_item_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
payment_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
other_order_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
stamp=$(date -u +%m%d%H%M%S)
order_number="E2E-$stamp"
idempotency_key="e2e:$order_id"

cleanup() {
  ssh "$vps" "docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q" <<SQL >/dev/null 2>&1 || true
DELETE FROM public.checkout_operations WHERE order_id IN ('$order_id'::uuid,'$other_order_id'::uuid);
DELETE FROM public.payments WHERE order_id IN ('$order_id'::uuid,'$other_order_id'::uuid);
DELETE FROM public.order_item_modifiers WHERE order_item_id IN (SELECT id FROM public.order_items WHERE order_id IN ('$order_id'::uuid,'$other_order_id'::uuid));
DELETE FROM public.order_items WHERE order_id IN ('$order_id'::uuid,'$other_order_id'::uuid);
DELETE FROM public.orders WHERE id IN ('$order_id'::uuid,'$other_order_id'::uuid);
DELETE FROM public.merchant_devices WHERE id='$device_id'::uuid;
DELETE FROM public.device_pairing_tokens WHERE id='$pairing_id'::uuid;
SQL
}
trap cleanup EXIT

order_payload=$(jq -nc --arg oid "$order_id" --arg onum "$order_number" --arg mid "$merchant_id" --arg bid "$branch_id" \
  --arg iid "$order_item_id" --arg menu "$item_id" --arg name "$item_name" --argjson price "$item_price" \
  '{p_order:{id:$oid,order_number:$onum,table_number:"QUICK",total:$price,subtotal:$price,tax:0,service_charge:0,status:"preparing",order_type:"takeaway",cashier_name:"Codex E2E",guest_count:1,merchant_id:$mid,branch_id:$bid,order_source:"staff",is_staff_confirmed:true},p_items:[{id:$iid,order_id:$oid,item_name:$name,quantity:1,price:$price,status:"cooking",item_id:$menu,merchant_id:$mid,branch_id:$bid}],p_modifiers:[]}')

for attempt in 1 2; do
  create_result=$(curl -fsS https://api.alphaposweb.com/rest/v1/rpc/create_order_atomic \
    -H "apikey: $anon_key" -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' -d "$order_payload")
  test "$(printf '%s' "$create_result" | jq -r '.status')" = 'ok'
done

checkout_payload=$(jq -nc --arg oid "$order_id" --arg key "$idempotency_key" --arg pid "$payment_id" --argjson price "$item_price" \
  '{p_order_id:$oid,p_idempotency_key:$key,p_payments:[{id:$pid,amount:$price,payment_method:"cash"}],p_table_number:"QUICK",p_breakdown:{grand_total:$price,subtotal:$price}}')
for attempt in 1 2; do
  checkout_result=$(curl -fsS https://api.alphaposweb.com/rest/v1/rpc/complete_checkout_atomic \
    -H "apikey: $anon_key" -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' -d "$checkout_payload")
  test "$(printf '%s' "$checkout_result" | jq -r '.status')" = 'completed'
done

ssh "$vps" "docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q" <<SQL
INSERT INTO public.orders(id,merchant_id,branch_id,order_number,table_number,total,status,created_at,updated_at)
VALUES('$other_order_id','$merchant_id','$other_branch','E2E-BR-$stamp','QUICK',1,'preparing',now(),now());
SQL

isolation_result=$(curl -fsS "https://api.alphaposweb.com/rest/v1/orders?id=eq.$other_order_id&select=id" \
  -H "apikey: $anon_key" -H "Authorization: Bearer $access_token")
test "$(printf '%s' "$isolation_result" | jq 'length')" = '0'

verify_json=$(ssh "$vps" "docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres -At" <<SQL
SELECT json_build_object(
 'orders',(SELECT count(*) FROM public.orders WHERE id='$order_id'),
 'items',(SELECT count(*) FROM public.order_items WHERE order_id='$order_id'),
 'payments',(SELECT count(*) FROM public.payments WHERE order_id='$order_id'),
 'checkout_ops',(SELECT count(*) FROM public.checkout_operations WHERE order_id='$order_id'),
 'status',(SELECT status FROM public.orders WHERE id='$order_id'),
 'branch',(SELECT branch_id FROM public.orders WHERE id='$order_id')
)::text;
SQL
)
test "$(printf '%s' "$verify_json" | jq -r '.orders')" = '1'
test "$(printf '%s' "$verify_json" | jq -r '.items')" = '1'
test "$(printf '%s' "$verify_json" | jq -r '.payments')" = '1'
test "$(printf '%s' "$verify_json" | jq -r '.checkout_ops')" = '1'
test "$(printf '%s' "$verify_json" | jq -r '.status')" = 'completed'
test "$(printf '%s' "$verify_json" | jq -r '.branch')" = "$branch_id"

printf 'PAIRING_BRANCH_CLAIM=%s\n' "$claimed_branch"
printf 'REFRESH_BRANCH_CLAIM=%s\n' "$refreshed_branch"
printf 'TRANSACTION_RESULT=%s\n' "$verify_json"
printf 'BRANCH_B_VISIBLE_ROWS=%s\n' "$(printf '%s' "$isolation_result" | jq 'length')"
printf 'CLEANUP=test rows and device removed on exit\n'
