BEGIN;

-- Merchant-device JWTs intentionally use role=anon with tenant and optional
-- branch claims. Keep table privileges aligned with the RLS policies that
-- enforce those claims.
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.restaurant_tables
TO anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.prep_recipes,
         public.prep_recipe_components,
         public.prep_production_batches
TO anon, authenticated, service_role;

DO $policies$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'prep_recipes', 'prep_recipe_components', 'prep_production_batches'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS merchant_device_isolation ON public.%I', table_name);
    EXECUTE format(
      'CREATE POLICY merchant_device_isolation ON public.%I FOR ALL TO anon USING (merchant_id = public.get_active_merchant_id()) WITH CHECK (merchant_id = public.get_active_merchant_id())',
      table_name
    );
  END LOOP;
END $policies$;

-- Re-publish the current RPC signature. This repairs environments where the
-- client was released before the corresponding migration reached PostgREST.
CREATE OR REPLACE FUNCTION public.apply_inventory_movement(
    p_movement_id UUID,
    p_merchant_id UUID,
    p_item_id UUID,
    p_type TEXT,
    p_quantity NUMERIC,
    p_reference_id UUID,
    p_branch_id UUID,
    p_cost_price NUMERIC,
    p_notes TEXT,
    p_reason_code TEXT,
    p_created_at TIMESTAMPTZ,
    p_audit_signature TEXT,
    p_business_date DATE,
    p_register_session_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_item_branch UUID;
BEGIN
    PERFORM public.assert_inventory_tenant(p_merchant_id);
    IF p_quantity IS NULL OR (p_quantity = 0 AND NOT (p_type = 'adjust' AND p_reason_code = 'stock_audit')) THEN
        RAISE EXCEPTION 'Inventory movement quantity must be non-zero';
    END IF;
    IF p_cost_price IS NOT NULL AND p_cost_price < 0 THEN
        RAISE EXCEPTION 'Inventory movement cost cannot be negative';
    END IF;

    SELECT branch_id INTO v_item_branch
    FROM public.inventory_items
    WHERE id = p_item_id AND merchant_id = p_merchant_id
      AND COALESCE(is_deleted, FALSE) = FALSE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active inventory item not found for merchant'; END IF;
    IF p_branch_id IS NOT NULL AND v_item_branch IS DISTINCT FROM p_branch_id THEN
        RAISE EXCEPTION 'Inventory movement branch does not match item branch';
    END IF;

    SELECT id INTO v_id FROM public.inventory_transactions
    WHERE id = p_movement_id
       OR (p_reference_id IS NOT NULL
           AND merchant_id = p_merchant_id AND item_id = p_item_id
           AND transaction_type = p_type AND reference_id = p_reference_id)
    LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    INSERT INTO public.inventory_transactions (
        id, merchant_id, item_id, item_name, transaction_type, type, quantity,
        reference_id, branch_id, cost_price, notes, reason_code, audit_signature,
        business_date, register_session_id,
        is_synced, is_deleted, created_at, updated_at
    ) VALUES (
        p_movement_id, p_merchant_id, p_item_id, '', p_type, p_type, p_quantity,
        p_reference_id, COALESCE(p_branch_id, v_item_branch), p_cost_price,
        p_notes, p_reason_code, p_audit_signature,
        p_business_date, p_register_session_id,
        TRUE, FALSE, COALESCE(p_created_at, now()), now()
    ) RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_inventory_movement(
    UUID, UUID, UUID, TEXT, NUMERIC, UUID, UUID, NUMERIC, TEXT, TEXT,
    TIMESTAMPTZ, TEXT, DATE, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_inventory_movement(
    UUID, UUID, UUID, TEXT, NUMERIC, UUID, UUID, NUMERIC, TEXT, TEXT,
    TIMESTAMPTZ, TEXT, DATE, UUID
) TO anon, authenticated, service_role;

-- Ask PostgREST to discover the repaired function immediately.
NOTIFY pgrst, 'reload schema';

COMMIT;
