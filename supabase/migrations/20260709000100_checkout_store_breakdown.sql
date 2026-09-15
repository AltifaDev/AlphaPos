-- =========================================================================
-- Migration: checkout_store_breakdown
-- Date: 2026-07-09
-- Problem: complete_checkout wrote only orders.total (the grand total paid).
--          orders.subtotal / tax / service_charge were left at their
--          submission-time defaults (often 0 for staff-phone / web orders),
--          so the POS displayed an inconsistent "Subtotal 0.00 / Total 90.00".
--
-- Fix: extend complete_checkout with optional p_subtotal / p_tax /
--      p_service_charge / p_discount params. When provided, persist them onto
--      the order so the stored breakdown matches the amount actually charged.
--      When omitted (older clients), derive a safe fallback: if subtotal is
--      still 0 but the order has a positive total, set subtotal = total so the
--      breakdown is never inconsistent.
--
-- Backward compatible: the original 6-arg signature keeps working because all
-- new parameters have defaults. PostgREST resolves the overload by argument
-- names, so existing callers are unaffected.
-- =========================================================================

CREATE OR REPLACE FUNCTION complete_checkout(
    p_payment_id      UUID,
    p_order_id        UUID,
    p_amount          DECIMAL,        -- grand total paid (incl. tax + service charge)
    p_method          VARCHAR,
    p_table_number    VARCHAR,
    p_grand_total     DECIMAL DEFAULT NULL,  -- alias kept for forward-compat; uses p_amount
    p_subtotal        DECIMAL DEFAULT NULL,  -- NEW: pre-tax subtotal
    p_tax             DECIMAL DEFAULT NULL,  -- NEW: tax amount
    p_service_charge  DECIMAL DEFAULT NULL,  -- NEW: service charge amount
    p_discount        DECIMAL DEFAULT NULL   -- NEW: discount amount
) RETURNS VOID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id         UUID;
    v_caller_merchant_id  UUID;
    v_amount_to_record    DECIMAL;
    v_order_total         DECIMAL;
    v_effective_subtotal  DECIMAL;
BEGIN
    -- ── Security: verify caller merchant matches order merchant ─────────────
    v_caller_merchant_id := get_merchant_id();

    SELECT merchant_id, total INTO v_merchant_id, v_order_total
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

    -- ── 1. Insert payment record ────────────────────────────────────────────
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

    -- ── 2. Mark order completed AND persist the amount breakdown ─────────────
    -- Prefer explicit values from the client. When a breakdown value is NULL,
    -- keep the order's current value. As a final safety net, if the resulting
    -- subtotal would still be 0 while the total is positive, set subtotal =
    -- total so the POS never shows "Subtotal 0 / Total N".
    v_effective_subtotal := COALESCE(
        p_subtotal,
        (SELECT subtotal FROM orders WHERE id = p_order_id)
    );
    IF (v_effective_subtotal IS NULL OR v_effective_subtotal = 0)
       AND COALESCE(v_amount_to_record, v_order_total, 0) > 0 THEN
        v_effective_subtotal := COALESCE(v_amount_to_record, v_order_total);
    END IF;

    UPDATE orders
    SET    status         = 'completed',
           subtotal       = v_effective_subtotal,
           tax            = COALESCE(p_tax, tax),
           service_charge = COALESCE(p_service_charge, service_charge),
           discount       = COALESCE(p_discount, discount),
           total          = COALESCE(v_amount_to_record, total),
           updated_at     = CURRENT_TIMESTAMP
    WHERE  id             = p_order_id
      AND  merchant_id    = v_merchant_id;

    -- ── 3. Mark all order_items as served ────────────────────────────────────
    UPDATE order_items
    SET    status = 'served'
    WHERE  order_id    = p_order_id
      AND  merchant_id = v_merchant_id
      AND  status     != 'cancelled';

    -- ── 4. Close active table session ─────────────────────────────────────────
    UPDATE table_sessions
    SET    is_active  = 0,
           ended_at   = CURRENT_TIMESTAMP
    WHERE  table_number = p_table_number
      AND  is_active    = 1
      AND  merchant_id  = v_merchant_id;

    -- ── 5. Reset restaurant_table status → cleaning ───────────────────────────
    UPDATE restaurant_tables
    SET    status     = 'cleaning',
           updated_at = CURRENT_TIMESTAMP
    WHERE  table_number = p_table_number
      AND  merchant_id  = v_merchant_id;

END;
$$ LANGUAGE plpgsql;

-- Grant execute for both the legacy 6-arg overload and the new 10-arg overload.
GRANT EXECUTE ON FUNCTION complete_checkout(UUID, UUID, DECIMAL, VARCHAR, VARCHAR, DECIMAL)
    TO authenticated, anon;
GRANT EXECUTE ON FUNCTION complete_checkout(UUID, UUID, DECIMAL, VARCHAR, VARCHAR, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL)
    TO authenticated, anon;

-- One-time backfill: repair historical rows where the breakdown is missing but
-- a total exists, so already-settled orders also display consistently.
UPDATE orders
SET    subtotal = total
WHERE  (subtotal IS NULL OR subtotal = 0)
  AND  total > 0;

-- =========================================================================
-- Legacy 6-arg overload: existing app builds still call complete_checkout
-- with only (payment_id, order_id, amount, method, table_number[, grand_total]).
-- PostgREST routes those calls to THIS overload, not the 10-arg one above, so
-- we must also repair it here — otherwise old clients keep writing an
-- inconsistent breakdown. This version applies the same subtotal fallback
-- (subtotal = total when the stored subtotal is 0) without requiring the
-- caller to send the breakdown explicitly.
-- =========================================================================
CREATE OR REPLACE FUNCTION complete_checkout(
    p_payment_id      UUID,
    p_order_id        UUID,
    p_amount          DECIMAL,
    p_method          VARCHAR,
    p_table_number    VARCHAR,
    p_grand_total     DECIMAL DEFAULT NULL
) RETURNS VOID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id         UUID;
    v_caller_merchant_id  UUID;
    v_amount_to_record    DECIMAL;
    v_order_total         DECIMAL;
    v_effective_subtotal  DECIMAL;
BEGIN
    v_caller_merchant_id := get_merchant_id();

    SELECT merchant_id, total INTO v_merchant_id, v_order_total
    FROM orders
    WHERE id = p_order_id;

    IF v_merchant_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    IF v_caller_merchant_id IS DISTINCT FROM v_merchant_id THEN
        RAISE EXCEPTION 'Permission denied: merchant mismatch (caller=%, order=%)',
            v_caller_merchant_id, v_merchant_id;
    END IF;

    v_amount_to_record := COALESCE(p_grand_total, p_amount);

    INSERT INTO payments (id, order_id, amount, payment_method, status, created_at, merchant_id)
    VALUES (
        p_payment_id, p_order_id, v_amount_to_record, p_method,
        'completed', CURRENT_TIMESTAMP, v_merchant_id
    )
    ON CONFLICT (id) DO NOTHING;

    -- Subtotal fallback so the POS never shows "Subtotal 0 / Total N".
    SELECT subtotal INTO v_effective_subtotal FROM orders WHERE id = p_order_id;
    IF (v_effective_subtotal IS NULL OR v_effective_subtotal = 0)
       AND COALESCE(v_amount_to_record, v_order_total, 0) > 0 THEN
        v_effective_subtotal := COALESCE(v_amount_to_record, v_order_total);
    END IF;

    UPDATE orders
    SET    status     = 'completed',
           subtotal   = v_effective_subtotal,
           total      = COALESCE(v_amount_to_record, total),
           updated_at = CURRENT_TIMESTAMP
    WHERE  id         = p_order_id
      AND  merchant_id = v_merchant_id;

    UPDATE order_items
    SET    status = 'served'
    WHERE  order_id    = p_order_id
      AND  merchant_id = v_merchant_id
      AND  status     != 'cancelled';

    UPDATE table_sessions
    SET    is_active = 0, ended_at = CURRENT_TIMESTAMP
    WHERE  table_number = p_table_number
      AND  is_active    = 1
      AND  merchant_id  = v_merchant_id;

    UPDATE restaurant_tables
    SET    status = 'cleaning', updated_at = CURRENT_TIMESTAMP
    WHERE  table_number = p_table_number
      AND  merchant_id  = v_merchant_id;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- create_customer_order: persist the order breakdown for web / customer orders.
-- The prior version inserted only total (subtotal/tax/service_charge left at
-- their defaults of 0), so web orders also showed "Subtotal 0 / Total N" in the
-- POS. Add the breakdown columns; COALESCE keeps older payloads (without the
-- breakdown) working by falling back to the total for subtotal.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.create_customer_order(
    p_order JSONB,
    p_items JSONB,
    p_modifiers JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_order_id UUID := (p_order->>'id')::UUID;
    v_merchant_id UUID := (p_order->>'merchant_id')::UUID;
    v_active_merchant UUID := public.get_active_merchant_id();
    v_total NUMERIC := COALESCE((p_order->>'total')::NUMERIC, 0);
    v_item JSONB;
    v_modifier JSONB;
BEGIN
    IF v_active_merchant IS NULL OR v_active_merchant <> v_merchant_id THEN
        RAISE EXCEPTION 'merchant mismatch';
    END IF;

    IF jsonb_array_length(COALESCE(p_items, '[]'::JSONB)) = 0 THEN
        RAISE EXCEPTION 'order must contain at least one item';
    END IF;

    INSERT INTO public.orders (
        id, order_number, table_number, total, subtotal, tax, service_charge, discount,
        status, session_token, guest_count, merchant_id, created_at
    ) VALUES (
        v_order_id,
        p_order->>'order_number',
        p_order->>'table_number',
        v_total,
        -- Fall back to total so subtotal is never a stray 0 for web orders.
        COALESCE(NULLIF((p_order->>'subtotal')::NUMERIC, 0), v_total),
        COALESCE((p_order->>'tax')::NUMERIC, 0),
        COALESCE((p_order->>'service_charge')::NUMERIC, 0),
        COALESCE((p_order->>'discount')::NUMERIC, 0),
        COALESCE(p_order->>'status', 'preparing'),
        NULLIF(p_order->>'session_token', ''),
        COALESCE((p_order->>'guest_count')::INTEGER, 1),
        v_merchant_id,
        COALESCE((p_order->>'created_at')::TIMESTAMPTZ, now())
    );

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO public.order_items (
            id, order_id, item_name, quantity, price, status,
            item_id, merchant_id, notes
        ) VALUES (
            (v_item->>'id')::UUID,
            v_order_id,
            v_item->>'item_name',
            (v_item->>'quantity')::INTEGER,
            (v_item->>'price')::NUMERIC,
            COALESCE(v_item->>'status', 'cooking'),
            NULLIF(v_item->>'item_id', ''),
            v_merchant_id,
            NULLIF(v_item->>'notes', '')
        );
    END LOOP;

    FOR v_modifier IN SELECT value FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB))
    LOOP
        INSERT INTO public.order_item_modifiers (
            id, order_item_id, modifier_id, price, merchant_id
        ) VALUES (
            (v_modifier->>'id')::UUID,
            (v_modifier->>'order_item_id')::UUID,
            (v_modifier->>'modifier_id')::UUID,
            COALESCE((v_modifier->>'price')::NUMERIC, 0),
            v_merchant_id
        );
    END LOOP;

    RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB) TO authenticated, anon;
