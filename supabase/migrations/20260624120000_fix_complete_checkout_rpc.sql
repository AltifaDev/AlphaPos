-- =========================================================================
-- Migration: fix_complete_checkout_rpc
-- Date: 2026-06-24
-- Problem: complete_checkout RPC was missing:
--   1. UPDATE orders SET status='completed'       → orders stayed as "preparing"
--   2. UPDATE restaurant_tables SET status='vacant' → table card stayed red
-- Also: added p_grand_total param so the payment record stores the full
--       amount-paid (including tax + service charge) instead of order.total alone.
-- =========================================================================

CREATE OR REPLACE FUNCTION complete_checkout(
    p_payment_id     UUID,
    p_order_id       UUID,
    p_amount         DECIMAL,        -- grand total paid (incl. tax + service charge)
    p_method         VARCHAR,
    p_table_number   VARCHAR,
    p_grand_total    DECIMAL DEFAULT NULL   -- alias kept for forward-compat; uses p_amount
) RETURNS VOID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id         UUID;
    v_caller_merchant_id  UUID;
    v_amount_to_record    DECIMAL;
BEGIN
    -- ── Security: verify caller merchant matches order merchant ────────────
    v_caller_merchant_id := get_merchant_id();

    SELECT merchant_id INTO v_merchant_id
    FROM orders
    WHERE id = p_order_id;

    IF v_merchant_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    IF v_caller_merchant_id IS DISTINCT FROM v_merchant_id THEN
        RAISE EXCEPTION 'Permission denied: merchant mismatch (caller=%, order=%)',
            v_caller_merchant_id, v_merchant_id;
    END IF;

    -- Use p_grand_total if provided (new callers), otherwise fall back to p_amount
    v_amount_to_record := COALESCE(p_grand_total, p_amount);

    -- ── 1. Insert payment record ───────────────────────────────────────────
    INSERT INTO payments (id, order_id, amount, payment_method, status, created_at, merchant_id)
    VALUES (
        p_payment_id,
        p_order_id,
        v_amount_to_record,
        p_method,
        'completed',
        CURRENT_TIMESTAMP,
        v_merchant_id
    )
    ON CONFLICT (id) DO NOTHING;   -- idempotent: retry-safe

    -- ── 2. Mark order as completed ─────────────────────────────────────────
    -- FIX: was missing — caused orders to remain "preparing" on all platforms
    UPDATE orders
    SET    status     = 'completed',
           updated_at = CURRENT_TIMESTAMP
    WHERE  id         = p_order_id
      AND  merchant_id = v_merchant_id;

    -- ── 3. Mark all order_items as served ──────────────────────────────────
    UPDATE order_items
    SET    status = 'served'
    WHERE  order_id    = p_order_id
      AND  merchant_id = v_merchant_id
      AND  status     != 'cancelled';

    -- ── 4. Close active table session ─────────────────────────────────────
    UPDATE table_sessions
    SET    is_active  = 0,
           ended_at   = CURRENT_TIMESTAMP
    WHERE  table_number = p_table_number
      AND  is_active    = 1
      AND  merchant_id  = v_merchant_id;

    -- ── 5. Reset restaurant_table status → cleaning ────────────────────────
    -- Set to 'cleaning' to support 'still dining' / 'pending status confirmation'
    UPDATE restaurant_tables
    SET    status     = 'cleaning',
           updated_at = CURRENT_TIMESTAMP
    WHERE  table_number = p_table_number
      AND  merchant_id  = v_merchant_id;

END;
$$ LANGUAGE plpgsql;

-- Grant execute permission to authenticated role (RLS will enforce merchant isolation)
GRANT EXECUTE ON FUNCTION complete_checkout(UUID, UUID, DECIMAL, VARCHAR, VARCHAR, DECIMAL)
    TO authenticated, anon;
