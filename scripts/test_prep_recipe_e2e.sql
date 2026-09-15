\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  m uuid; b uuid;
  raw_a uuid := gen_random_uuid(); raw_b uuid := gen_random_uuid(); output_item uuid := gen_random_uuid();
  prep_id uuid := gen_random_uuid(); batch_id uuid := gen_random_uuid(); failed_batch_id uuid := gen_random_uuid();
  result jsonb; qty_a numeric; qty_b numeric; qty_output numeric; transaction_count integer;
  failed boolean := false;
BEGIN
  SELECT id INTO m FROM public.merchants ORDER BY created_at LIMIT 1;
  SELECT id INTO b FROM public.branches WHERE merchant_id=m ORDER BY created_at LIMIT 1;
  IF m IS NULL OR b IS NULL THEN RAISE EXCEPTION 'test_requires_merchant_and_branch'; END IF;
  PERFORM set_config('request.jwt.claims',json_build_object(
    'app_metadata',json_build_object('merchant_id',m::text))::text,true);

  INSERT INTO public.inventory_items(id,merchant_id,branch_id,name,sku,unit,current_quantity,reorder_level,cost_price,is_synced,is_deleted)
  VALUES
    (raw_a,m,b,'E2E rice noodle','PREP-A-'||raw_a,'g',1000,0,0.10,true,false),
    (raw_b,m,b,'E2E seasoning','PREP-B-'||raw_b,'g',1000,0,0.20,true,false),
    (output_item,m,b,'E2E prepared noodle','PREP-O-'||output_item,'g',0,0,0,true,false);
  INSERT INTO public.inventory_lots(id,merchant_id,branch_id,inventory_item_id,lot_number,initial_quantity,remaining_quantity,lot_cost_price,is_synced)
  VALUES
    (gen_random_uuid(),m,b,raw_a,'RAW-A',1000,1000,0.10,true),
    (gen_random_uuid(),m,b,raw_b,'RAW-B',1000,1000,0.20,true);

  INSERT INTO public.prep_recipes(id,merchant_id,name,output_inventory_item_id,expected_output_quantity,output_unit)
  VALUES(prep_id,m,'E2E prepared noodle',output_item,500,'g');
  INSERT INTO public.prep_recipe_components(merchant_id,prep_recipe_id,ingredient_inventory_item_id,quantity,quantity_unit)
  VALUES(m,prep_id,raw_a,300,'g'),(m,prep_id,raw_b,100,'g');

  result := public.produce_prep_recipe_batch(batch_id,m,b,prep_id,1,500,'PREP-001',NULL,'E2E');
  SELECT current_quantity INTO qty_a FROM public.inventory_items WHERE id=raw_a;
  SELECT current_quantity INTO qty_b FROM public.inventory_items WHERE id=raw_b;
  SELECT current_quantity INTO qty_output FROM public.inventory_items WHERE id=output_item;
  IF qty_a<>700 OR qty_b<>900 OR qty_output<>500 THEN
    RAISE EXCEPTION 'atomic production mismatch: raw_a %, raw_b %, output %',qty_a,qty_b,qty_output;
  END IF;
  IF abs((result->>'unit_cost')::numeric-0.10)>0.000001 THEN
    RAISE EXCEPTION 'actual-yield unit cost mismatch: %',result;
  END IF;

  result := public.produce_prep_recipe_batch(batch_id,m,b,prep_id,1,500,'PREP-001',NULL,'retry');
  SELECT count(*) INTO transaction_count FROM public.inventory_transactions WHERE reference_id=batch_id;
  IF COALESCE((result->>'duplicate')::boolean,false) IS NOT TRUE OR transaction_count<>3 THEN
    RAISE EXCEPTION 'idempotency mismatch: result %, transactions %',result,transaction_count;
  END IF;

  BEGIN
    PERFORM public.produce_prep_recipe_batch(failed_batch_id,m,b,prep_id,10,5000,'PREP-FAIL',NULL,'must roll back');
  EXCEPTION WHEN OTHERS THEN failed := SQLERRM LIKE 'insufficient_component_stock:%'; END;
  IF NOT failed THEN RAISE EXCEPTION 'insufficient batch was not rejected'; END IF;
  SELECT current_quantity INTO qty_a FROM public.inventory_items WHERE id=raw_a;
  SELECT current_quantity INTO qty_b FROM public.inventory_items WHERE id=raw_b;
  SELECT current_quantity INTO qty_output FROM public.inventory_items WHERE id=output_item;
  IF qty_a<>700 OR qty_b<>900 OR qty_output<>500 THEN
    RAISE EXCEPTION 'failed batch changed stock: raw_a %, raw_b %, output %',qty_a,qty_b,qty_output;
  END IF;

  -- A sale consumes only the prepared output. Raw ingredients were already consumed by production.
  PERFORM public.apply_inventory_movement(gen_random_uuid(),m,output_item,'sell',230,gen_random_uuid(),b,0.10,'E2E sale','sale',now(),NULL);
  SELECT current_quantity INTO qty_a FROM public.inventory_items WHERE id=raw_a;
  SELECT current_quantity INTO qty_b FROM public.inventory_items WHERE id=raw_b;
  SELECT current_quantity INTO qty_output FROM public.inventory_items WHERE id=output_item;
  IF qty_a<>700 OR qty_b<>900 OR qty_output<>270 THEN
    RAISE EXCEPTION 'sale double-deducted components: raw_a %, raw_b %, output %',qty_a,qty_b,qty_output;
  END IF;
  RAISE NOTICE 'PASS prep recipe E2E: atomic production, actual-yield cost, idempotency, rollback, output-only sale';
END $$;

ROLLBACK;
