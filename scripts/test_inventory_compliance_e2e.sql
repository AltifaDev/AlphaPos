\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  m uuid; b1 uuid; b2 uuid; s uuid := gen_random_uuid(); t uuid := gen_random_uuid();
  lot uuid := gen_random_uuid(); recall_id uuid := gen_random_uuid(); transfer_id uuid := gen_random_uuid();
  before_qty numeric; failed boolean := false;
  transfer_result jsonb; request_count integer;
BEGIN
  SELECT id INTO m FROM public.merchants ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object(
      'app_metadata', json_build_object('merchant_id', m::text)
  )::text, true);
  SELECT id INTO b1 FROM public.branches WHERE merchant_id = m ORDER BY created_at LIMIT 1;
  SELECT id INTO b2 FROM public.branches WHERE merchant_id = m AND id <> b1 ORDER BY created_at LIMIT 1;
  IF m IS NULL OR b1 IS NULL THEN RAISE EXCEPTION 'test_requires_merchant_and_branch'; END IF;
  IF b2 IS NULL THEN
    b2 := gen_random_uuid();
    INSERT INTO public.branches(id,merchant_id,name,branch_code)
    VALUES(b2,m,'Compliance E2E Target','E2E-'||substr(b2::text,1,8));
  END IF;

  INSERT INTO public.inventory_items(id, merchant_id, branch_id, name, sku, unit,
      current_quantity, reorder_level, cost_price, is_synced, is_deleted)
  VALUES (s,m,b1,'Compliance source','C-S-'||s,'piece',10,0,1,true,false);
  INSERT INTO public.inventory_items(id, merchant_id, branch_id, name, sku, unit,
      current_quantity, reorder_level, cost_price, is_synced, is_deleted)
  VALUES (t,m,b2,'Compliance target','C-T-'||t,'piece',0,0,1,true,false);
  INSERT INTO public.inventory_lots(id,merchant_id,branch_id,inventory_item_id,lot_number,
      initial_quantity,remaining_quantity,lot_cost_price,is_synced)
  VALUES(lot,m,b1,s,'RECALL-ME',10,10,1,true);

  INSERT INTO public.inventory_recalls(id,merchant_id,recall_number,title,reason_code)
  VALUES(recall_id,m,'TEST-'||recall_id,'E2E recall','quality_failure');
  INSERT INTO public.inventory_recall_lots(id,merchant_id,recall_id,lot_id,inventory_item_id,
      branch_id,affected_quantity) VALUES(gen_random_uuid(),m,recall_id,lot,s,b1,10);
  PERFORM public.activate_inventory_recall(recall_id,m,NULL);

  BEGIN
    PERFORM public.transfer_inventory_compliant(transfer_id,m,s,t,1,NULL,NULL,'must be blocked');
  EXCEPTION WHEN OTHERS THEN failed := SQLERRM = 'insufficient_released_stock'; END;
  IF NOT failed THEN RAISE EXCEPTION 'recalled lot was transferable'; END IF;

  UPDATE public.inventory_lot_controls SET disposition='released',released_at=now() WHERE lot_id=lot;
  transfer_result := public.transfer_inventory_compliant(transfer_id,m,s,t,1,NULL,NULL,'released transfer');
  SELECT count(*) INTO request_count FROM public.inventory_transfer_requests WHERE id=transfer_id;
  RAISE NOTICE 'first transfer result=%, requests=%', transfer_result, request_count;
  -- Simulates another terminal retrying the same request.
  transfer_result := public.transfer_inventory_compliant(transfer_id,m,s,t,1,NULL,NULL,'duplicate retry');
  SELECT count(*) INTO request_count FROM public.inventory_transfer_requests WHERE id=transfer_id;
  RAISE NOTICE 'retry transfer result=%, requests=%', transfer_result, request_count;
  SELECT current_quantity INTO before_qty FROM public.inventory_items WHERE id=s;
  IF before_qty <> 9 THEN RAISE EXCEPTION 'idempotent transfer expected 9, got %', before_qty; END IF;
  RAISE NOTICE 'PASS inventory compliance E2E: recall/quarantine/release/idempotent transfer';
END $$;

ROLLBACK;
