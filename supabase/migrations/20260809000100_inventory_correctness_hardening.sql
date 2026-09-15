BEGIN;

-- Inventory writes are privileged operations. A missing tenant context must
-- fail closed; accepting a caller-provided merchant id without a verified
-- request context would bypass RLS through SECURITY DEFINER functions.
CREATE OR REPLACE FUNCTION public.assert_inventory_tenant(p_merchant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_active UUID := public.get_active_merchant_id();
BEGIN
    IF v_active IS NULL THEN
        RAISE EXCEPTION 'Authenticated merchant context is required';
    END IF;
    IF v_active <> p_merchant_id THEN
        RAISE EXCEPTION 'Merchant scope mismatch';
    END IF;
END;
$$;

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
    p_audit_signature TEXT
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
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active inventory item not found for merchant';
    END IF;
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
        is_synced, is_deleted, created_at, updated_at
    ) VALUES (
        p_movement_id, p_merchant_id, p_item_id, '', p_type, p_type, p_quantity,
        p_reference_id, COALESCE(p_branch_id, v_item_branch), p_cost_price,
        p_notes, p_reason_code, p_audit_signature, TRUE, FALSE,
        COALESCE(p_created_at, now()), now()
    ) RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_inventory_atomic(
    p_transfer_id UUID,
    p_merchant_id UUID,
    p_source_item_id UUID,
    p_target_item_id UUID,
    p_quantity NUMERIC,
    p_notes TEXT
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
        SELECT count(*) = 2
        FROM public.inventory_transactions
        WHERE merchant_id = p_merchant_id AND reference_id = p_transfer_id
          AND ((item_id = p_source_item_id AND transaction_type = 'transfer_out')
            OR (item_id = p_target_item_id AND transaction_type = 'transfer_in'))
    ) THEN
        RETURN p_transfer_id;
    END IF;

    PERFORM id FROM public.inventory_items
    WHERE id IN (p_source_item_id, p_target_item_id)
      AND merchant_id = p_merchant_id AND COALESCE(is_deleted, FALSE) = FALSE
    ORDER BY id FOR UPDATE;
    SELECT * INTO v_source FROM public.inventory_items
      WHERE id = p_source_item_id AND merchant_id = p_merchant_id;
    SELECT * INTO v_target FROM public.inventory_items
      WHERE id = p_target_item_id AND merchant_id = p_merchant_id;
    IF v_source.id IS NULL OR v_target.id IS NULL THEN
        RAISE EXCEPTION 'Transfer item not found';
    END IF;
    IF v_source.branch_id IS NULL OR v_target.branch_id IS NULL
       OR v_source.branch_id = v_target.branch_id THEN
        RAISE EXCEPTION 'Transfer requires two distinct branches';
    END IF;
    IF v_source.current_quantity < p_quantity THEN
        RAISE EXCEPTION 'Insufficient source stock';
    END IF;

    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), p_merchant_id, p_source_item_id, 'transfer_out',
        p_quantity, p_transfer_id, v_source.branch_id, v_source.cost_price,
        p_notes, 'transfer', now(), NULL
    );
    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), p_merchant_id, p_target_item_id, 'transfer_in',
        p_quantity, p_transfer_id, v_target.branch_id, v_source.cost_price,
        p_notes, 'transfer', now(), NULL
    );
    RETURN p_transfer_id;
END;
$$;

-- New rows are validated immediately while legacy anomalies can be repaired
-- explicitly before VALIDATE CONSTRAINT in a later controlled migration.
ALTER TABLE public.inventory_items
    DROP CONSTRAINT IF EXISTS inventory_items_nonnegative_cost,
    ADD CONSTRAINT inventory_items_nonnegative_cost
        CHECK (cost_price >= 0) NOT VALID;
ALTER TABLE public.inventory_transactions
    DROP CONSTRAINT IF EXISTS inventory_transactions_nonzero_quantity,
    ADD CONSTRAINT inventory_transactions_nonzero_quantity
        CHECK (quantity <> 0 OR (transaction_type = 'adjust' AND reason_code = 'stock_audit')) NOT VALID,
    DROP CONSTRAINT IF EXISTS inventory_transactions_nonnegative_cost,
    ADD CONSTRAINT inventory_transactions_nonnegative_cost
        CHECK (cost_price IS NULL OR cost_price >= 0) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_inventory_items_branch_sku_normalized
    ON public.inventory_items (merchant_id, branch_id, lower(trim(sku)))
    WHERE COALESCE(is_deleted, FALSE) = FALSE AND NULLIF(trim(sku), '') IS NOT NULL;

-- The transaction ledger and its allocation rows are append-only to application
-- clients. SECURITY DEFINER movement functions and database triggers retain write
-- access as owners, while normal clients can only read their own tenant rows.
REVOKE INSERT, UPDATE, DELETE ON public.inventory_transactions FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.inventory_lot_allocations FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.assert_inventory_tenant(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_inventory_tenant(UUID)
    TO anon, authenticated, service_role;

COMMIT;
