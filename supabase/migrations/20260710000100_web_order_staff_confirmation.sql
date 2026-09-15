-- =========================================================================
-- Migration: web_order_staff_confirmation
-- Date: 2026-07-10
-- Problem: Web (customer self-ordering) orders were written with their line
--          items already in status 'cooking'. The always-connected iPad
--          station reacts to the realtime orders/order_items change and
--          printed the kitchen/bar/sticker tickets IMMEDIATELY, with no staff
--          confirmation step. The requirement is that only iPad / iPhone can
--          send an order to the kitchen, and a web order must be confirmed by
--          staff on an iPad/iPhone before any ticket prints.
--
-- Fix (three parts, this file covers the database contract):
--   1. Add orders.order_source  ('pos' | 'staff' | 'web') to record channel.
--   2. Add orders.is_staff_confirmed (BOOLEAN) — the print gate. Web orders
--      default to FALSE; all other channels default to TRUE.
--   3. Update create_customer_order() so web orders persist order_source /
--      is_staff_confirmed and their items default to 'pending' (not 'cooking'),
--      which surfaces the existing POS "pending self-orders" approval banner.
--
-- Backward compatible: columns have defaults; the RPC keeps its 3-arg
-- signature and COALESCEs missing payload keys, so older web clients that
-- omit the new fields still insert successfully (treated as a web order
-- awaiting confirmation).
-- =========================================================================

-- ── 1 + 2. Schema columns ────────────────────────────────────────────────
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS order_source TEXT NOT NULL DEFAULT 'pos';

ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS is_staff_confirmed BOOLEAN NOT NULL DEFAULT TRUE;

-- Backfill any pre-existing web orders so they are treated as already
-- confirmed (they were printed under the old immediate-print behaviour and
-- must not re-surface as pending after this migration deploys).
UPDATE public.orders
   SET is_staff_confirmed = TRUE
 WHERE order_source = 'web'
   AND is_staff_confirmed IS DISTINCT FROM TRUE
   AND status IN ('ready', 'served', 'completed', 'cancelled');

COMMENT ON COLUMN public.orders.order_source IS
    'Channel the order originated from: pos (iPad), staff (iPhone), web (customer web ordering).';
COMMENT ON COLUMN public.orders.is_staff_confirmed IS
    'Kitchen-print gate. Web orders start FALSE and are flipped TRUE when staff approve on the iPad/iPhone. POS/staff orders default TRUE.';

-- ── 3. Updated create_customer_order RPC ─────────────────────────────────
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
    -- Channel + confirmation gate. Default to a web order awaiting staff
    -- confirmation so a payload that forgets these keys still holds the order.
    v_order_source TEXT := COALESCE(p_order->>'order_source', 'web');
    v_is_confirmed BOOLEAN := COALESCE((p_order->>'is_staff_confirmed')::BOOLEAN,
                                       v_order_source <> 'web');
    -- Web orders must wait for staff approval, so their lines start 'pending'.
    -- Non-web callers may still pass an explicit per-item status.
    v_default_item_status TEXT := CASE WHEN v_order_source = 'web'
                                       THEN 'pending' ELSE 'cooking' END;
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
        status, order_source, is_staff_confirmed,
        session_token, guest_count, merchant_id, created_at
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
        v_order_source,
        v_is_confirmed,
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
            -- Honour an explicit item status if present; otherwise use the
            -- channel default (web => pending, holding it out of the kitchen).
            COALESCE(v_item->>'status', v_default_item_status),
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
