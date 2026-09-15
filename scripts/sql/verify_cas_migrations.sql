\set ON_ERROR_STOP on
BEGIN;

DO $verify$
DECLARE
  v_merchant uuid;
  v_branch uuid;
  v_table text;
  v_order record;
  v_result jsonb;
BEGIN
  SELECT id INTO v_merchant FROM public.merchants ORDER BY created_at NULLS LAST LIMIT 1;
  IF v_merchant IS NULL THEN RAISE EXCEPTION 'verification requires a merchant'; END IF;
  PERFORM set_config('request.jwt.claims', jsonb_build_object('merchant_id',v_merchant)::text, true);

  SELECT id INTO v_branch FROM public.branches WHERE merchant_id=v_merchant LIMIT 1;

  v_result := public.upsert_purchase_order_atomic_cas(
    jsonb_build_object(
      'id',gen_random_uuid(),'merchant_id',v_merchant,'branch_id',v_branch,
      'po_number','CAS-VERIFY-'||gen_random_uuid()::text,'status','draft',
      'order_date',now(),'updated_at',now(),'currency_code','THB'
    ), '[]'::jsonb
  );
  IF COALESCE((v_result->>'purchase_order_row_version')::bigint,0) < 1 THEN
    RAISE EXCEPTION 'purchase order CAS did not return a revision';
  END IF;

  SELECT table_number INTO v_table FROM public.restaurant_tables
   WHERE merchant_id=v_merchant AND (v_branch IS NULL OR branch_id=v_branch) LIMIT 1;
  IF v_table IS NOT NULL THEN
    v_result := public.upsert_table_session_cas(jsonb_build_object(
      'id',gen_random_uuid(),'merchant_id',v_merchant,'branch_id',v_branch,
      'table_number',v_table,'session_token','cas-verify-'||gen_random_uuid()::text,
      'is_active',0,'guest_count',1,'cashier_name','migration-verifier','created_at',now()
    ));
    IF COALESCE((v_result->>'row_version')::bigint,0) < 1 THEN
      RAISE EXCEPTION 'table session CAS did not return a revision';
    END IF;
  END IF;

  SELECT id,merchant_id,order_number,row_version INTO v_order
    FROM public.orders WHERE merchant_id=v_merchant LIMIT 1;
  IF v_order.id IS NOT NULL THEN
    BEGIN
      PERFORM public.create_order_atomic_cas(
        jsonb_build_object(
          'id',v_order.id,'merchant_id',v_order.merchant_id,
          'order_number',v_order.order_number,'session_token','migration-verifier',
          'expected_row_version',v_order.row_version + 1
        ), '[]'::jsonb, '[]'::jsonb
      );
      RAISE EXCEPTION 'stale order revision was accepted';
    EXCEPTION WHEN serialization_failure THEN
      NULL;
    END;
  END IF;
END
$verify$;

ROLLBACK;
