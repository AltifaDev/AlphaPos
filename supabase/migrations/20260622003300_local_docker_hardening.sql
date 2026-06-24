-- Reconcile the Local Docker schema after the legacy 009/016 migration split.
-- This migration is deliberately forward-only: previously applied migrations
-- remain immutable and every environment converges on the same final schema.

BEGIN;

-- Customer orders carry the table-session token used by the web checkout RPC.
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS session_token TEXT;

CREATE INDEX IF NOT EXISTS idx_orders_session_token
    ON public.orders (session_token)
    WHERE session_token IS NOT NULL;

-- Both columns are INTEGER in the legacy schema (0/1), not BOOLEAN.
CREATE OR REPLACE FUNCTION public.get_table_guest_count(
    p_table_id UUID,
    p_merchant_id UUID
)
RETURNS INTEGER
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT COALESCE((
        SELECT guest_count
        FROM public.table_sessions
        WHERE table_id = p_table_id
          AND merchant_id = p_merchant_id
          AND is_active = 1
          AND is_deleted = false
        ORDER BY started_at DESC
        LIMIT 1
    ), 1);
$$;

-- Migration 015 removed permissive policies but assumed replacement policies
-- existed. Recreate strict tenant policies explicitly.
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders;
DROP POLICY IF EXISTS "merchant_isolation_orders" ON public.orders;
CREATE POLICY "merchant_isolation_orders"
    ON public.orders FOR ALL TO public
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

DROP POLICY IF EXISTS "table_sessions_merchant_access" ON public.table_sessions;
DROP POLICY IF EXISTS "merchant_isolation_table_sessions" ON public.table_sessions;
CREATE POLICY "merchant_isolation_table_sessions"
    ON public.table_sessions FOR ALL TO public
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

CREATE OR REPLACE FUNCTION public.create_customer_order(
    p_order JSONB,
    p_items JSONB,
    p_modifiers JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_order_id UUID := (p_order->>'id')::UUID;
    v_merchant_id UUID := (p_order->>'merchant_id')::UUID;
    v_active_merchant UUID := public.get_active_merchant_id();
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
        id, order_number, table_number, total, status, session_token,
        guest_count, merchant_id, created_at
    ) VALUES (
        v_order_id,
        p_order->>'order_number',
        p_order->>'table_number',
        COALESCE((p_order->>'total')::NUMERIC, 0),
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

    FOR v_modifier IN
        SELECT value FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB))
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

GRANT EXECUTE ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB)
    TO anon, authenticated;

-- Avoid references to a temporary relation during function validation. Dynamic
-- column lists also keep archive tables usable when live tables gain columns.
CREATE OR REPLACE PROCEDURE public.archive_historical_data(
    p_months_older_than INT DEFAULT 12
)
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_cutoff_date TIMESTAMPTZ;
    v_order_ids UUID[];
    v_columns TEXT;
BEGIN
    IF p_months_older_than < 1 THEN
        RAISE EXCEPTION 'p_months_older_than must be at least 1';
    END IF;

    v_cutoff_date := CURRENT_TIMESTAMP - make_interval(months => p_months_older_than);

    SELECT array_agg(id) INTO v_order_ids
    FROM public.orders
    WHERE created_at < v_cutoff_date;

    IF COALESCE(array_length(v_order_ids, 1), 0) > 0 THEN
        SELECT string_agg(format('%I', live.attname), ', ' ORDER BY live.attnum)
        INTO v_columns
        FROM pg_attribute live
        WHERE live.attrelid = 'public.order_items'::regclass
          AND live.attnum > 0 AND NOT live.attisdropped
          AND EXISTS (
              SELECT 1 FROM pg_attribute archived
              WHERE archived.attrelid = 'public.order_items_archive'::regclass
                AND archived.attname = live.attname
                AND archived.attnum > 0 AND NOT archived.attisdropped
          );

        EXECUTE format(
            'WITH moved AS (DELETE FROM public.order_items WHERE order_id = ANY($1) RETURNING *) '
            'INSERT INTO public.order_items_archive (%1$s) SELECT %1$s FROM moved ON CONFLICT (id) DO NOTHING',
            v_columns
        ) USING v_order_ids;

        SELECT string_agg(format('%I', live.attname), ', ' ORDER BY live.attnum)
        INTO v_columns
        FROM pg_attribute live
        WHERE live.attrelid = 'public.orders'::regclass
          AND live.attnum > 0 AND NOT live.attisdropped
          AND EXISTS (
              SELECT 1 FROM pg_attribute archived
              WHERE archived.attrelid = 'public.orders_archive'::regclass
                AND archived.attname = live.attname
                AND archived.attnum > 0 AND NOT archived.attisdropped
          );

        EXECUTE format(
            'WITH moved AS (DELETE FROM public.orders WHERE id = ANY($1) RETURNING *) '
            'INSERT INTO public.orders_archive (%1$s) SELECT %1$s FROM moved ON CONFLICT (id) DO NOTHING',
            v_columns
        ) USING v_order_ids;
    END IF;

    SELECT string_agg(format('%I', live.attname), ', ' ORDER BY live.attnum)
    INTO v_columns
    FROM pg_attribute live
    WHERE live.attrelid = 'public.audit_logs'::regclass
      AND live.attnum > 0 AND NOT live.attisdropped
      AND EXISTS (
          SELECT 1 FROM pg_attribute archived
          WHERE archived.attrelid = 'public.audit_logs_archive'::regclass
            AND archived.attname = live.attname
            AND archived.attnum > 0 AND NOT archived.attisdropped
      );

    EXECUTE format(
        'WITH moved AS (DELETE FROM public.audit_logs WHERE created_at < $1 RETURNING *) '
        'INSERT INTO public.audit_logs_archive (%1$s) SELECT %1$s FROM moved ON CONFLICT (id) DO NOTHING',
        v_columns
    ) USING v_cutoff_date;
END;
$$;

COMMIT;
