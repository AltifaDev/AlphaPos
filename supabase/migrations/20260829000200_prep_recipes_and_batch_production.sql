BEGIN;

CREATE TABLE IF NOT EXISTS public.prep_recipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name text NOT NULL,
  output_inventory_item_id uuid NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
  expected_output_quantity numeric NOT NULL CHECK (expected_output_quantity > 0),
  output_unit text NOT NULL,
  instructions text,
  is_active boolean NOT NULL DEFAULT true,
  is_synced boolean NOT NULL DEFAULT true,
  is_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, output_inventory_item_id)
);

CREATE TABLE IF NOT EXISTS public.prep_recipe_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  prep_recipe_id uuid NOT NULL REFERENCES public.prep_recipes(id) ON DELETE CASCADE,
  ingredient_inventory_item_id uuid NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
  quantity numeric NOT NULL CHECK (quantity > 0),
  quantity_unit text NOT NULL,
  is_synced boolean NOT NULL DEFAULT true,
  is_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, prep_recipe_id, ingredient_inventory_item_id)
);

CREATE TABLE IF NOT EXISTS public.prep_production_batches (
  id uuid PRIMARY KEY,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  prep_recipe_id uuid NOT NULL REFERENCES public.prep_recipes(id) ON DELETE RESTRICT,
  batch_count numeric NOT NULL CHECK (batch_count > 0),
  actual_output_quantity numeric NOT NULL CHECK (actual_output_quantity > 0),
  lot_number text,
  produced_by_employee_id uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  produced_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  total_component_cost numeric NOT NULL DEFAULT 0,
  output_unit_cost numeric NOT NULL DEFAULT 0,
  is_synced boolean NOT NULL DEFAULT true,
  is_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prep_components_recipe
  ON public.prep_recipe_components(merchant_id, prep_recipe_id) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_prep_batches_recipe_date
  ON public.prep_production_batches(merchant_id, prep_recipe_id, produced_at DESC);

ALTER TABLE public.prep_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prep_recipe_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prep_production_batches ENABLE ROW LEVEL SECURITY;

DO $policies$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['prep_recipes','prep_recipe_components','prep_production_batches'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS merchant_isolation ON public.%I', table_name);
    EXECUTE format('CREATE POLICY merchant_isolation ON public.%I FOR ALL TO authenticated, service_role USING (merchant_id = public.get_active_merchant_id()) WITH CHECK (merchant_id = public.get_active_merchant_id())', table_name);
  END LOOP;
END $policies$;

ALTER TABLE public.inventory_transactions DROP CONSTRAINT IF EXISTS inventory_transactions_type_check;
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_type_check CHECK (
  COALESCE(transaction_type, type) IN (
    'receive','waste','adjust','sell','void','opening','return_to_supplier',
    'refund_return','transfer_out','transfer_in','production_consume','production_output'
  )
);

CREATE OR REPLACE FUNCTION public.inventory_movement_before_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_type text := COALESCE(NULLIF(NEW.transaction_type,''),NEW.type);
DECLARE v_item public.inventory_items%ROWTYPE;
BEGIN
  IF v_type NOT IN ('receive','waste','adjust','sell','void','opening','return_to_supplier',
      'refund_return','transfer_out','transfer_in','production_consume','production_output')
  THEN RAISE EXCEPTION 'Unsupported inventory movement type: %',v_type; END IF;
  SELECT * INTO v_item FROM public.inventory_items
   WHERE id=NEW.item_id AND merchant_id=NEW.merchant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventory item not found for merchant'; END IF;
  NEW.transaction_type:=v_type; NEW.type:=v_type;
  NEW.quantity:=CASE
    WHEN v_type IN ('receive','void','opening','refund_return','transfer_in','production_output') THEN abs(NEW.quantity)
    WHEN v_type IN ('sell','waste','return_to_supplier','transfer_out','production_consume') THEN -abs(NEW.quantity)
    ELSE NEW.quantity END;
  IF v_item.current_quantity + NEW.quantity < -0.0001 THEN
    RAISE EXCEPTION 'Insufficient stock: item %, available %, requested %',NEW.item_id,v_item.current_quantity,abs(NEW.quantity);
  END IF;
  NEW.item_name:=COALESCE(NULLIF(NEW.item_name,''),v_item.name);
  NEW.cost_price:=COALESCE(NEW.cost_price,v_item.cost_price);
  NEW.branch_id:=COALESCE(NEW.branch_id,v_item.branch_id);
  NEW.created_at:=COALESCE(NEW.created_at,now()); NEW.updated_at:=COALESCE(NEW.updated_at,now());
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.inventory_movement_after_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_remaining numeric:=abs(NEW.quantity); DECLARE v_take numeric;
DECLARE v_lot record; DECLARE v_original record;
BEGIN
  UPDATE public.inventory_items SET current_quantity=current_quantity+NEW.quantity,
    updated_at=now(),is_synced=true WHERE id=NEW.item_id AND merchant_id=NEW.merchant_id;
  IF NEW.transaction_type IN ('sell','waste','return_to_supplier','transfer_out','production_consume') THEN
    FOR v_lot IN SELECT * FROM public.inventory_lots
      WHERE merchant_id=NEW.merchant_id AND inventory_item_id=NEW.item_id
        AND NOT COALESCE(is_deleted,false) AND remaining_quantity>0
      ORDER BY expiry_date ASC NULLS LAST,received_date ASC,id FOR UPDATE
    LOOP
      EXIT WHEN v_remaining<=0; v_take:=least(v_remaining,v_lot.remaining_quantity);
      UPDATE public.inventory_lots SET remaining_quantity=remaining_quantity-v_take,
        updated_at=now(),is_synced=true WHERE id=v_lot.id;
      INSERT INTO public.inventory_lot_allocations(merchant_id,movement_id,reference_id,
        inventory_item_id,lot_id,quantity,cost_price)
      VALUES(NEW.merchant_id,NEW.id,NEW.reference_id,NEW.item_id,v_lot.id,v_take,v_lot.lot_cost_price)
      ON CONFLICT(movement_id,lot_id) DO NOTHING;
      v_remaining:=v_remaining-v_take;
    END LOOP;
  ELSIF NEW.transaction_type IN ('void','refund_return') AND NEW.reference_id IS NOT NULL THEN
    FOR v_original IN SELECT a.lot_id,a.quantity FROM public.inventory_transactions t
      JOIN public.inventory_lot_allocations a ON a.movement_id=t.id
      WHERE t.merchant_id=NEW.merchant_id AND t.item_id=NEW.item_id
        AND t.reference_id=NEW.reference_id AND t.transaction_type='sell'
    LOOP
      UPDATE public.inventory_lots SET remaining_quantity=least(initial_quantity,remaining_quantity+v_original.quantity),
        updated_at=now(),is_synced=true WHERE id=v_original.lot_id;
    END LOOP;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.produce_prep_recipe_batch(
  p_batch_id uuid, p_merchant_id uuid, p_branch_id uuid, p_prep_recipe_id uuid,
  p_batch_count numeric, p_actual_output_quantity numeric, p_lot_number text,
  p_produced_by uuid, p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
SET statement_timeout='30s' SET lock_timeout='5s' AS $$
DECLARE recipe_row public.prep_recipes%ROWTYPE;
DECLARE component record; DECLARE required_qty numeric; DECLARE total_cost numeric:=0;
DECLARE unit_cost numeric; DECLARE existing public.prep_production_batches%ROWTYPE;
DECLARE configured_component_count integer; DECLARE branch_component_count integer;
BEGIN
  IF public.get_active_merchant_id() IS NOT NULL AND public.get_active_merchant_id()<>p_merchant_id
  THEN RAISE EXCEPTION 'merchant_scope_mismatch'; END IF;
  IF p_batch_count<=0 OR p_actual_output_quantity<=0 THEN RAISE EXCEPTION 'invalid_batch_quantity'; END IF;
  SELECT * INTO existing FROM public.prep_production_batches WHERE id=p_batch_id;
  IF FOUND THEN
    IF existing.merchant_id<>p_merchant_id OR existing.prep_recipe_id<>p_prep_recipe_id
    THEN RAISE EXCEPTION 'batch_id_reused_with_different_payload'; END IF;
    RETURN jsonb_build_object('batch_id',p_batch_id,'duplicate',true,
      'output_quantity',existing.actual_output_quantity,'unit_cost',existing.output_unit_cost);
  END IF;
  SELECT * INTO recipe_row FROM public.prep_recipes
   WHERE id=p_prep_recipe_id AND merchant_id=p_merchant_id AND is_active AND NOT is_deleted FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'prep_recipe_not_found'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.inventory_items
    WHERE id=recipe_row.output_inventory_item_id AND merchant_id=p_merchant_id
      AND branch_id=p_branch_id AND NOT is_deleted)
  THEN RAISE EXCEPTION 'prep_output_branch_mismatch'; END IF;
  SELECT count(*) INTO configured_component_count
    FROM public.prep_recipe_components
    WHERE merchant_id=p_merchant_id AND prep_recipe_id=p_prep_recipe_id AND NOT is_deleted;
  SELECT count(*) INTO branch_component_count
    FROM public.prep_recipe_components c
    JOIN public.inventory_items i ON i.id=c.ingredient_inventory_item_id
    WHERE c.merchant_id=p_merchant_id AND c.prep_recipe_id=p_prep_recipe_id AND NOT c.is_deleted
      AND i.merchant_id=p_merchant_id AND i.branch_id=p_branch_id AND NOT i.is_deleted;
  IF configured_component_count=0 THEN RAISE EXCEPTION 'prep_recipe_has_no_components'; END IF;
  IF branch_component_count<>configured_component_count
  THEN RAISE EXCEPTION 'prep_component_branch_mismatch'; END IF;
  PERFORM id FROM public.inventory_items
   WHERE merchant_id=p_merchant_id AND branch_id=p_branch_id
     AND id IN (SELECT ingredient_inventory_item_id FROM public.prep_recipe_components
                WHERE prep_recipe_id=p_prep_recipe_id AND NOT is_deleted
                UNION SELECT recipe_row.output_inventory_item_id)
   ORDER BY id FOR UPDATE;
  FOR component IN
    SELECT c.*,i.unit,i.cost_price,i.current_quantity
    FROM public.prep_recipe_components c JOIN public.inventory_items i ON i.id=c.ingredient_inventory_item_id
    WHERE c.merchant_id=p_merchant_id AND c.prep_recipe_id=p_prep_recipe_id AND NOT c.is_deleted
      AND NOT i.is_deleted AND i.branch_id=p_branch_id
  LOOP
    IF component.ingredient_inventory_item_id=recipe_row.output_inventory_item_id
    THEN RAISE EXCEPTION 'prep_recipe_cycle_detected'; END IF;
    required_qty:=public.inventory_required_quantity(component.quantity,component.quantity_unit,
      component.unit,100,p_batch_count);
    IF component.current_quantity<required_qty THEN RAISE EXCEPTION 'insufficient_component_stock: %',component.ingredient_inventory_item_id; END IF;
    total_cost:=total_cost+(required_qty*component.cost_price);
    PERFORM public.apply_inventory_movement(gen_random_uuid(),p_merchant_id,
      component.ingredient_inventory_item_id,'production_consume',required_qty,p_batch_id,p_branch_id,
      component.cost_price,'Prep batch '||recipe_row.name,'production',now(),NULL);
  END LOOP;
  unit_cost:=total_cost/p_actual_output_quantity;
  PERFORM public.apply_inventory_movement(gen_random_uuid(),p_merchant_id,
    recipe_row.output_inventory_item_id,'production_output',p_actual_output_quantity,p_batch_id,p_branch_id,
    unit_cost,'Prep batch output '||recipe_row.name,'production',now(),NULL);
  INSERT INTO public.prep_production_batches(id,merchant_id,branch_id,prep_recipe_id,batch_count,
    actual_output_quantity,lot_number,produced_by_employee_id,notes,total_component_cost,output_unit_cost)
  VALUES(p_batch_id,p_merchant_id,p_branch_id,p_prep_recipe_id,p_batch_count,p_actual_output_quantity,
    NULLIF(trim(p_lot_number),''),p_produced_by,p_notes,total_cost,unit_cost);
  IF NULLIF(trim(p_lot_number),'') IS NOT NULL THEN
    INSERT INTO public.inventory_lots(id,merchant_id,branch_id,inventory_item_id,lot_number,
      received_date,initial_quantity,remaining_quantity,lot_cost_price,is_synced,is_deleted,created_at,updated_at)
    VALUES(gen_random_uuid(),p_merchant_id,p_branch_id,recipe_row.output_inventory_item_id,trim(p_lot_number),
      now(),p_actual_output_quantity,p_actual_output_quantity,unit_cost,true,false,now(),now());
  END IF;
  RETURN jsonb_build_object('batch_id',p_batch_id,'duplicate',false,
    'output_quantity',p_actual_output_quantity,'total_cost',total_cost,'unit_cost',unit_cost);
END $$;

REVOKE ALL ON FUNCTION public.produce_prep_recipe_batch(uuid,uuid,uuid,uuid,numeric,numeric,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.produce_prep_recipe_batch(uuid,uuid,uuid,uuid,numeric,numeric,text,uuid,text) TO authenticated,service_role;

COMMIT;
