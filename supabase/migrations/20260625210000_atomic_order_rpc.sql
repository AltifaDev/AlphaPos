-- ============================================================================
-- Migration: Atomic Order RPC (มาตรฐานสากล — Single Transaction)
-- 
-- แก้ปัญหา: POST orders + POST order_items แยก → partial commit ได้
-- Solution: RPC เดียวที่รัน BEGIN ... COMMIT ทำให้ atomic — either both or none
--
-- รองรับ:
--   1. iPad (AlphaPos) — JWT authenticated, ไม่มี session_token
--   2. Web (customer-order-web) — มี session_token จาก QR code
--   3. Idempotent retry — ON CONFLICT DO UPDATE ปลอดภัยเรียกซ้ำ
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(
    p_order    JSONB,
    p_items    JSONB,
    p_modifiers JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order_id     UUID   := (p_order->>'id')::UUID;
    v_merchant_id  UUID   := (p_order->>'merchant_id')::UUID;
    v_active_merchant UUID := public.get_active_merchant_id();
    v_session_token TEXT   := NULLIF(p_order->>'session_token', '');
    v_item         JSONB;
    v_modifier     JSONB;
    v_item_count   INT    := 0;
BEGIN
    -- ── 1. Auth check ────────────────────────────────────────────────────────
    -- iPad ส่ง JWT → v_active_merchant = v_merchant_id → ผ่าน
    -- Web order ส่ง session_token → check table_sessions → ผ่าน
    IF v_active_merchant IS DISTINCT FROM v_merchant_id THEN
        IF v_session_token IS NULL THEN
            RAISE EXCEPTION 'auth_required: merchant JWT or session_token required';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.table_sessions ts
            WHERE ts.merchant_id   = v_merchant_id
              AND ts.session_token = v_session_token
              AND ts.is_active     = 1
              AND COALESCE(ts.is_deleted, false) = false
        ) THEN
            RAISE EXCEPTION 'session_invalid: no active table session for token';
        END IF;
    END IF;

    -- ── 2. Items validation ───────────────────────────────────────────────────
    IF jsonb_array_length(COALESCE(p_items, '[]'::JSONB)) = 0 THEN
        RAISE EXCEPTION 'items_required: order must contain at least one item';
    END IF;

    -- ── 3. Upsert order (idempotent — safe to retry) ──────────────────────────
    INSERT INTO public.orders (
        id, order_number, table_number, total, status,
        session_token, guest_count, merchant_id, created_at, updated_at,
        delivery_brand, delivery_gp, delivery_ad_fee,
        delivery_ad_fee_is_pct, delivery_other_fee,
        is_deleted
    ) VALUES (
        v_order_id,
        p_order->>'order_number',
        p_order->>'table_number',
        COALESCE((p_order->>'total')::NUMERIC, 0),
        COALESCE(p_order->>'status', 'preparing'),
        v_session_token,
        COALESCE((p_order->>'guest_count')::INTEGER, 1),
        v_merchant_id,
        COALESCE((p_order->>'created_at')::TIMESTAMPTZ, now()),
        COALESCE((p_order->>'updated_at')::TIMESTAMPTZ, now()),
        COALESCE(p_order->>'delivery_brand', ''),
        COALESCE((p_order->>'delivery_gp')::NUMERIC, 0),
        COALESCE((p_order->>'delivery_ad_fee')::NUMERIC, 0),
        COALESCE((p_order->>'delivery_ad_fee_is_pct')::BOOLEAN, false),
        COALESCE((p_order->>'delivery_other_fee')::NUMERIC, 0),
        false
    )
    ON CONFLICT (id) DO UPDATE SET
        status                 = EXCLUDED.status,
        total                  = EXCLUDED.total,
        updated_at             = EXCLUDED.updated_at,
        delivery_brand         = EXCLUDED.delivery_brand,
        delivery_gp            = EXCLUDED.delivery_gp,
        delivery_ad_fee        = EXCLUDED.delivery_ad_fee,
        delivery_ad_fee_is_pct = EXCLUDED.delivery_ad_fee_is_pct,
        delivery_other_fee     = EXCLUDED.delivery_other_fee;

    -- ── 4. Upsert order_items (idempotent) ────────────────────────────────────
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO public.order_items (
            id, order_id, item_name, quantity, price, status,
            item_id, merchant_id, notes, served_by, created_at
        ) VALUES (
            (v_item->>'id')::UUID,
            v_order_id,
            v_item->>'item_name',
            (v_item->>'quantity')::INTEGER,
            (v_item->>'price')::NUMERIC,
            COALESCE(v_item->>'status', 'cooking'),
            NULLIF(v_item->>'item_id', ''),
            v_merchant_id,
            NULLIF(v_item->>'notes', ''),
            NULLIF(v_item->>'served_by', ''),
            COALESCE((v_item->>'created_at')::TIMESTAMPTZ, now())
        )
        ON CONFLICT (id) DO UPDATE SET
            status    = EXCLUDED.status,
            quantity  = EXCLUDED.quantity,
            notes     = EXCLUDED.notes,
            served_by = EXCLUDED.served_by;

        v_item_count := v_item_count + 1;
    END LOOP;

    -- ── 5. Upsert modifiers (optional) ───────────────────────────────────────
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
        )
        ON CONFLICT (id) DO NOTHING;
    END LOOP;

    -- ── 6. Return summary (ช่วย Swift confirm success) ───────────────────────
    RETURN jsonb_build_object(
        'order_id',    v_order_id,
        'items_count', v_item_count,
        'status',      'ok'
    );

EXCEPTION
    WHEN OTHERS THEN
        -- PostgreSQL auto-rollback transaction บน exception
        RAISE;
END;
$$;

-- Grant execute ให้ anon + authenticated (RLS ดูแลโดย auth check ใน function)
GRANT EXECUTE ON FUNCTION public.create_order_atomic(JSONB, JSONB, JSONB)
    TO anon, authenticated;

-- ─── Apply indexes ด้วย (idempotent) ────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON public.order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_merchant_id
    ON public.order_items (merchant_id);
CREATE INDEX IF NOT EXISTS idx_order_items_merchant_order
    ON public.order_items (merchant_id, order_id);
CREATE INDEX IF NOT EXISTS idx_orders_merchant_status
    ON public.orders (merchant_id, status)
    WHERE is_deleted = false;
