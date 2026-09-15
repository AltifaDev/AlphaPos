-- =========================================================================
-- Quick Order / counter-service standards
-- - Sequential daily queue numbers (works with VARCHAR or INTEGER queue_number)
-- - Sequential daily receipt numbers (RCP-YYYYMMDD-NNN)
-- - Broaden order_type vocabulary (take_out / takeaway / walk_in / delivery)
-- - Persist receipt_number through create_order_atomic
-- =========================================================================

BEGIN;

-- Ensure receipt_number exists (idempotent; also added in enterprise_compliance)
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS receipt_number VARCHAR(50);

-- Normalize queue_number to VARCHAR so values like Q-015 persist safely
-- (older migration attempted INTEGER; VARCHAR from extended_columns takes precedence).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND column_name = 'queue_number'
          AND data_type IN ('integer', 'bigint', 'smallint', 'numeric')
    ) THEN
        ALTER TABLE public.orders
            ALTER COLUMN queue_number TYPE VARCHAR(20)
            USING queue_number::TEXT;
    END IF;
END $$;

-- -------------------------------------------------------------------------
-- generate_queue_number — next daily queue for counter / quick / delivery
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_queue_number(
    p_merchant_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_next_queue INTEGER;
BEGIN
    SELECT COALESCE(MAX(
        CASE
            WHEN NULLIF(regexp_replace(COALESCE(queue_number::TEXT, ''), '[^0-9]', '', 'g'), '') IS NULL
                THEN NULL
            ELSE NULLIF(regexp_replace(COALESCE(queue_number::TEXT, ''), '[^0-9]', '', 'g'), '')::INTEGER
        END
    ), 0) + 1
    INTO v_next_queue
    FROM public.orders
    WHERE merchant_id = p_merchant_id
      AND created_at::DATE = CURRENT_DATE
      AND COALESCE(is_deleted, false) = false
      AND (
          order_type IN ('takeaway', 'take_out', 'delivery', 'walk_in')
          OR UPPER(COALESCE(table_number, '')) = 'QUICK'
          OR (
              COALESCE(table_number, '') = ''
              AND order_type IS DISTINCT FROM 'dine_in'
          )
      );

    RETURN v_next_queue;
END;
$$;

COMMENT ON FUNCTION public.generate_queue_number(UUID) IS
    'Returns next daily queue integer for quick/counter/delivery orders';

-- -------------------------------------------------------------------------
-- generate_receipt_number — RCP-YYYYMMDD-NNN per merchant per day
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_receipt_number(
    p_merchant_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_date TEXT := to_char((NOW() AT TIME ZONE 'Asia/Bangkok')::DATE, 'YYYYMMDD');
    v_next INTEGER;
BEGIN
    SELECT COALESCE(MAX(
        CASE
            WHEN receipt_number ~ ('^RCP-' || v_date || '-[0-9]{1,6}$')
                THEN substring(receipt_number FROM '[0-9]+$')::INTEGER
            ELSE NULL
        END
    ), 0) + 1
    INTO v_next
    FROM public.orders
    WHERE merchant_id = p_merchant_id
      AND COALESCE(is_deleted, false) = false
      AND receipt_number IS NOT NULL
      AND receipt_number LIKE ('RCP-' || v_date || '-%');

    RETURN 'RCP-' || v_date || '-' || lpad(v_next::TEXT, 3, '0');
END;
$$;

COMMENT ON FUNCTION public.generate_receipt_number(UUID) IS
    'Returns next daily receipt number RCP-YYYYMMDD-NNN (Asia/Bangkok day boundary)';

GRANT EXECUTE ON FUNCTION public.generate_queue_number(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_receipt_number(UUID) TO anon, authenticated;

-- -------------------------------------------------------------------------
-- create_order_atomic — persist receipt_number + order_source flags
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_order_atomic(
    p_order     JSONB,
    p_items     JSONB,
    p_modifiers JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order_id         UUID   := (p_order->>'id')::UUID;
    v_merchant_id      UUID   := (p_order->>'merchant_id')::UUID;
    v_active_merchant  UUID   := public.get_active_merchant_id();
    v_session_token    TEXT   := NULLIF(p_order->>'session_token', '');
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

    INSERT INTO public.orders (
        id, order_number, table_number, total, status,
        order_type, cashier_name, queue_number, receipt_number,
        session_token, guest_count, merchant_id, created_at, updated_at,
        delivery_brand, delivery_gp, delivery_ad_fee,
        delivery_ad_fee_is_pct, delivery_other_fee,
        order_source, is_staff_confirmed,
        is_deleted
    ) VALUES (
        v_order_id,
        p_order->>'order_number',
        p_order->>'table_number',
        COALESCE((p_order->>'total')::NUMERIC, 0),
        COALESCE(p_order->>'status', 'preparing'),
        COALESCE(p_order->>'order_type', 'dine_in'),
        COALESCE(NULLIF(p_order->>'cashier_name', ''), 'Staff'),
        NULLIF(p_order->>'queue_number', ''),
        NULLIF(p_order->>'receipt_number', ''),
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
        COALESCE(NULLIF(p_order->>'order_source', ''), 'pos'),
        COALESCE((p_order->>'is_staff_confirmed')::BOOLEAN, true),
        false
    )
    ON CONFLICT (id) DO UPDATE SET
        status                 = EXCLUDED.status,
        total                  = EXCLUDED.total,
        order_type             = EXCLUDED.order_type,
        cashier_name           = EXCLUDED.cashier_name,
        queue_number           = COALESCE(EXCLUDED.queue_number, public.orders.queue_number),
        receipt_number         = COALESCE(EXCLUDED.receipt_number, public.orders.receipt_number),
        updated_at             = EXCLUDED.updated_at,
        delivery_brand         = EXCLUDED.delivery_brand,
        delivery_gp            = EXCLUDED.delivery_gp,
        delivery_ad_fee        = EXCLUDED.delivery_ad_fee,
        delivery_ad_fee_is_pct = EXCLUDED.delivery_ad_fee_is_pct,
        delivery_other_fee     = EXCLUDED.delivery_other_fee,
        order_source           = COALESCE(EXCLUDED.order_source, public.orders.order_source),
        is_staff_confirmed     = COALESCE(EXCLUDED.is_staff_confirmed, public.orders.is_staff_confirmed);

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
        ON CONFLICT (id) DO UPDATE SET
            price = EXCLUDED.price;
    END LOOP;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'items_count', v_item_count,
        'status', 'ok'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_atomic(JSONB, JSONB, JSONB) TO anon, authenticated;

COMMIT;
