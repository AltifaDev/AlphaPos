BEGIN;

-- Keep business-day/session metadata inside the same privileged, idempotent
-- operation as the immutable movement. Clients cannot PATCH the append-only
-- ledger after INSERT (and must not need permission to do so).
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

CREATE OR REPLACE FUNCTION public.transfer_inventory_atomic(
    p_transfer_id UUID,
    p_merchant_id UUID,
    p_source_item_id UUID,
    p_target_item_id UUID,
    p_quantity NUMERIC,
    p_notes TEXT,
    p_created_at TIMESTAMPTZ,
    p_business_date DATE,
    p_register_session_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_source public.inventory_items%ROWTYPE;
    v_target public.inventory_items%ROWTYPE;
BEGIN
    PERFORM public.assert_inventory_tenant(p_merchant_id);
    IF p_quantity IS NULL OR p_quantity <= 0 OR p_source_item_id = p_target_item_id THEN
        RAISE EXCEPTION 'Invalid transfer';
    END IF;
    IF (
        SELECT count(*) = 2 FROM public.inventory_transactions
        WHERE merchant_id = p_merchant_id AND reference_id = p_transfer_id
          AND ((item_id = p_source_item_id AND transaction_type = 'transfer_out')
            OR (item_id = p_target_item_id AND transaction_type = 'transfer_in'))
    ) THEN RETURN p_transfer_id; END IF;

    PERFORM id FROM public.inventory_items
    WHERE id IN (p_source_item_id, p_target_item_id) AND merchant_id = p_merchant_id
    ORDER BY id FOR UPDATE;
    SELECT * INTO v_source FROM public.inventory_items WHERE id = p_source_item_id;
    SELECT * INTO v_target FROM public.inventory_items WHERE id = p_target_item_id;
    IF v_source.id IS NULL OR v_target.id IS NULL THEN RAISE EXCEPTION 'Transfer item not found'; END IF;
    IF v_source.current_quantity < p_quantity THEN RAISE EXCEPTION 'Insufficient source stock'; END IF;

    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), p_merchant_id, p_source_item_id, 'transfer_out',
        p_quantity, p_transfer_id, v_source.branch_id, v_source.cost_price,
        p_notes, 'transfer', p_created_at, NULL, p_business_date, p_register_session_id
    );
    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), p_merchant_id, p_target_item_id, 'transfer_in',
        p_quantity, p_transfer_id, v_target.branch_id, v_source.cost_price,
        p_notes, 'transfer', p_created_at, NULL, p_business_date, p_register_session_id
    );
    RETURN p_transfer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_inventory_atomic(
    UUID, UUID, UUID, UUID, NUMERIC, TEXT, TIMESTAMPTZ, DATE, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_inventory_atomic(
    UUID, UUID, UUID, UUID, NUMERIC, TEXT, TIMESTAMPTZ, DATE, UUID
) TO anon, authenticated, service_role;

COMMIT;
