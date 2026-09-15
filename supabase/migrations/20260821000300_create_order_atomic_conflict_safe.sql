-- ==============================================================================
-- Migration: Conflict-Safe create_order_atomic with branch_id
-- Date: 2026-08-21
-- Purpose: Prevent branch_id = null and orders_merchant_order_number_key violation
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order jsonb, p_items jsonb, p_modifiers jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_order_id         UUID   := (p_order->>'id')::UUID;
    v_merchant_id      UUID   := (p_order->>'merchant_id')::UUID;
    v_active_merchant  UUID   := public.get_active_merchant_id();
    v_session_token    TEXT   := NULLIF(p_order->>'session_token', '');
    v_order_number     TEXT   := NULLIF(TRIM(p_order->>'order_number'), '');
    v_branch_id        UUID   := COALESCE(NULLIF(p_order->>'branch_id', '')::UUID, public.get_active_branch_id());
    v_existing_id      UUID;
    v_item             JSONB;
    v_modifier         JSONB;
    v_item_count       INT    := 0;
BEGIN
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

    IF jsonb_array_length(COALESCE(p_items, '[]'::JSONB)) = 0 THEN
        RAISE EXCEPTION 'items_required: order must contain at least one item';
    END IF;

    -- If an order with this (merchant_id, order_number) already exists, reuse its canonical ID
    IF v_order_number IS NOT NULL THEN
        SELECT id INTO v_existing_id 
        FROM public.orders 
        WHERE merchant_id = v_merchant_id AND order_number = v_order_number
        LIMIT 1;
        
        IF v_existing_id IS NOT NULL THEN
            v_order_id := v_existing_id;
        END IF;
    END IF;

    INSERT INTO public.orders (
        id, order_number, table_number, total, status,
        order_type, cashier_name, queue_number, receipt_number,
        created_at, updated_at, merchant_id, branch_id, session_token,
        ready_at, delivery_brand, delivery_gp, delivery_ad_fee,
        delivery_ad_fee_is_pct, delivery_other_fee,
        platform_order_number, order_source, is_staff_confirmed,
        is_deleted
    ) VALUES (
        v_order_id,
        COALESCE(v_order_number, 'ORD-' || substring(v_order_id::text from 1 for 8)),
        COALESCE(NULLIF(p_order->>'table_number', ''), 'QUICK'),
        COALESCE((p_order->>'total')::NUMERIC, 0),
        COALESCE(p_order->>'status', 'preparing'),
        COALESCE(p_order->>'order_type', 'dine_in'),
        COALESCE(p_order->>'cashier_name', 'Staff'),
        NULLIF(p_order->>'queue_number', ''),
        NULLIF(p_order->>'receipt_number', ''),
        COALESCE((p_order->>'created_at')::TIMESTAMPTZ, now()),
        COALESCE((p_order->>'updated_at')::TIMESTAMPTZ, now()),
        v_merchant_id,
        v_branch_id,
        v_session_token,
        (p_order->>'ready_at')::TIMESTAMPTZ,
        NULLIF(p_order->>'delivery_brand', ''),
        COALESCE((p_order->>'delivery_gp')::NUMERIC, 0),
        COALESCE((p_order->>'delivery_ad_fee')::NUMERIC, 0),
        COALESCE((p_order->>'delivery_ad_fee_is_pct')::BOOLEAN, false),
        COALESCE((p_order->>'delivery_other_fee')::NUMERIC, 0),
        NULLIF(TRIM(COALESCE(p_order->>'platform_order_number', '')), ''),
        COALESCE(NULLIF(p_order->>'order_source', ''), 'pos'),
        COALESCE((p_order->>'is_staff_confirmed')::BOOLEAN, true),
        false
    )
    ON CONFLICT (id) DO UPDATE SET
        status                 = EXCLUDED.status,
        total                  = EXCLUDED.total,
        order_type             = EXCLUDED.order_type,
        cashier_name           = EXCLUDED.cashier_name,
        branch_id              = COALESCE(EXCLUDED.branch_id, public.orders.branch_id),
        queue_number           = COALESCE(EXCLUDED.queue_number, public.orders.queue_number),
        receipt_number         = COALESCE(EXCLUDED.receipt_number, public.orders.receipt_number),
        updated_at             = EXCLUDED.updated_at,
        delivery_brand         = EXCLUDED.delivery_brand,
        delivery_gp            = EXCLUDED.delivery_gp,
        delivery_ad_fee        = EXCLUDED.delivery_ad_fee,
        delivery_ad_fee_is_pct = EXCLUDED.delivery_ad_fee_is_pct,
        delivery_other_fee     = EXCLUDED.delivery_other_fee,
        platform_order_number  = COALESCE(EXCLUDED.platform_order_number, public.orders.platform_order_number),
        order_source           = COALESCE(EXCLUDED.order_source, public.orders.order_source),
        is_staff_confirmed     = COALESCE(EXCLUDED.is_staff_confirmed, public.orders.is_staff_confirmed);

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO public.order_items (
            id, order_id, item_name, quantity, price, status,
            item_id, merchant_id, branch_id, notes, served_by, created_at
        ) VALUES (
            (v_item->>'id')::UUID,
            v_order_id,
            v_item->>'item_name',
            (v_item->>'quantity')::INTEGER,
            (v_item->>'price')::NUMERIC,
            COALESCE(v_item->>'status', 'cooking'),
            NULLIF(v_item->>'item_id', ''),
            v_merchant_id,
            COALESCE(NULLIF(v_item->>'branch_id', '')::UUID, v_branch_id),
            NULLIF(v_item->>'notes', ''),
            NULLIF(v_item->>'served_by', ''),
            COALESCE((v_item->>'created_at')::TIMESTAMPTZ, now())
        )
        ON CONFLICT (id) DO UPDATE SET
            quantity   = EXCLUDED.quantity,
            price      = EXCLUDED.price,
            status     = EXCLUDED.status,
            item_name  = EXCLUDED.item_name,
            notes      = EXCLUDED.notes,
            served_by  = EXCLUDED.served_by;

        v_item_count := v_item_count + 1;
    END LOOP;

    FOR v_modifier IN SELECT value FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB))
    LOOP
        INSERT INTO public.order_item_modifiers (
            id, order_item_id, modifier_id, price, merchant_id
        ) VALUES (
            (v_modifier->>'id')::UUID,
            (v_modifier->>'order_item_id')::UUID,
            NULLIF(v_modifier->>'modifier_id', '')::UUID,
            COALESCE((v_modifier->>'price')::NUMERIC, 0),
            v_merchant_id
        )
        ON CONFLICT (id) DO NOTHING;
    END LOOP;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'items_count', v_item_count,
        'status', 'ok'
    );
END;
$function$;
