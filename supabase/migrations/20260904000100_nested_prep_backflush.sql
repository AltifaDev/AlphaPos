-- Backflush nested prep recipes at the sale event.  Prep outputs are virtual:
-- only raw leaves receive sell movements, so a batch cannot be consumed twice.
BEGIN;

CREATE OR REPLACE FUNCTION public.resolve_backflush_leaves(
  p_merchant_id uuid, p_branch_id uuid, p_item_id uuid, p_required numeric,
  p_path uuid[] DEFAULT ARRAY[]::uuid[]
) RETURNS TABLE(item_id uuid, quantity numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_prep public.prep_recipes%ROWTYPE; v_component record; v_output numeric;
BEGIN
  IF p_required <= 0 THEN RETURN; END IF;
  IF p_item_id = ANY(p_path) THEN RAISE EXCEPTION 'prep_recipe_cycle_detected'; END IF;
  SELECT * INTO v_prep FROM public.prep_recipes
   WHERE merchant_id=p_merchant_id AND output_inventory_item_id=p_item_id
     AND is_active AND NOT is_deleted LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT p_item_id, p_required;
    RETURN;
  END IF;
  SELECT public.inventory_required_quantity(v_prep.expected_output_quantity, v_prep.output_unit,
      i.unit, 100, 1) INTO v_output FROM public.inventory_items i WHERE i.id=p_item_id;
  IF COALESCE(v_output,0) <= 0 THEN RAISE EXCEPTION 'invalid_prep_output_quantity'; END IF;
  FOR v_component IN
    SELECT c.ingredient_inventory_item_id, c.quantity, c.quantity_unit, i.unit
    FROM public.prep_recipe_components c JOIN public.inventory_items i ON i.id=c.ingredient_inventory_item_id
    WHERE c.merchant_id=p_merchant_id AND c.prep_recipe_id=v_prep.id
      AND NOT c.is_deleted AND NOT i.is_deleted AND i.branch_id=p_branch_id
  LOOP
    RETURN QUERY SELECT * FROM public.resolve_backflush_leaves(
      p_merchant_id,p_branch_id,v_component.ingredient_inventory_item_id,
      public.inventory_required_quantity(v_component.quantity,v_component.quantity_unit,v_component.unit,100,1)
        * p_required / v_output,
      p_path || p_item_id
    );
  END LOOP;
END $$;

-- Replace the sale trigger's direct recipe deduction with leaf-level backflush.
CREATE OR REPLACE FUNCTION public.deduct_stock_on_order_item_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r record; leaf record; v_branch_id uuid; v_required numeric;
BEGIN
  IF NOT (NEW.status IN ('cooking','served') AND (TG_OP='INSERT' OR OLD.status IS NULL OR OLD.status='pending')) THEN RETURN NEW; END IF;
  v_branch_id:=COALESCE(NEW.branch_id,(SELECT branch_id FROM public.orders WHERE id=NEW.order_id));
  FOR r IN SELECT x.inventory_item_id,x.quantity_required,x.quantity_unit,x.yield_percentage,i.unit,i.cost_price
    FROM public.recipes x JOIN public.inventory_items i ON i.id=x.inventory_item_id
    WHERE x.menu_item_id=NEW.item_id AND x.merchant_id=NEW.merchant_id
      AND NOT COALESCE(x.is_deleted,FALSE) AND NOT COALESCE(i.is_deleted,FALSE)
      AND (v_branch_id IS NULL OR i.branch_id=v_branch_id)
  LOOP
    v_required:=public.inventory_required_quantity(r.quantity_required,r.quantity_unit,r.unit,r.yield_percentage,NEW.quantity);
    FOR leaf IN SELECT item_id,sum(quantity) quantity FROM public.resolve_backflush_leaves(NEW.merchant_id,v_branch_id,r.inventory_item_id,v_required) GROUP BY item_id LOOP
      PERFORM public.apply_inventory_movement(gen_random_uuid(),NEW.merchant_id,leaf.item_id,'sell',leaf.quantity,NEW.id,v_branch_id,
        (SELECT cost_price FROM public.inventory_items WHERE id=leaf.item_id),'Order item backflush '||NEW.id,'sale',now(),NULL);
    END LOOP;
  END LOOP;
  FOR r IN SELECT m.inventory_item_id,m.quantity_required,m.name,oim.id AS reference_id
    FROM public.order_item_modifiers oim JOIN public.modifiers m ON m.id=oim.modifier_id
    JOIN public.inventory_items i ON i.id=m.inventory_item_id
    WHERE oim.order_item_id=NEW.id AND NOT COALESCE(oim.is_deleted,FALSE)
      AND NOT COALESCE(m.is_deleted,FALSE) AND NOT COALESCE(i.is_deleted,FALSE)
      AND (v_branch_id IS NULL OR i.branch_id=v_branch_id)
  LOOP
    FOR leaf IN SELECT item_id,sum(quantity) quantity
      FROM public.resolve_backflush_leaves(NEW.merchant_id,v_branch_id,r.inventory_item_id,
        greatest(COALESCE(r.quantity_required,0),0)*NEW.quantity) GROUP BY item_id
    LOOP
      PERFORM public.apply_inventory_movement(gen_random_uuid(),NEW.merchant_id,leaf.item_id,'sell',leaf.quantity,r.reference_id,v_branch_id,
        (SELECT cost_price FROM public.inventory_items WHERE id=leaf.item_id),'Order modifier backflush '||r.name,'sale',now(),NULL);
    END LOOP;
  END LOOP;
  RETURN NEW;
END $$;

-- Reject any manual/API batch production in this mode; the exception rolls back
-- the whole RPC transaction before it can create component movements.
CREATE OR REPLACE FUNCTION public.reject_prep_batch_in_backflush_mode()
RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'prep_batch_production_disabled_in_backflush_mode'; END $$;
DROP TRIGGER IF EXISTS prevent_prep_batch_production_in_backflush_mode ON public.prep_production_batches;
CREATE TRIGGER prevent_prep_batch_production_in_backflush_mode BEFORE INSERT ON public.prep_production_batches
FOR EACH ROW EXECUTE FUNCTION public.reject_prep_batch_in_backflush_mode();

COMMIT;
