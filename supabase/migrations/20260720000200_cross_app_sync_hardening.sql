-- Cross-app sync hardening:
-- 1) Server-side price validation in create_customer_order (single write path)
-- 2) row_version optimistic concurrency on operational tables
-- 3) sync_outbox for idempotent push/print jobs + get_sync_health RPC
-- 4) Publish order_item_modifiers to Realtime

-- ═══════════════════════════════════════════════════════════════════════════
-- A. Optimistic concurrency: row_version
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS row_version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.order_items
    ADD COLUMN IF NOT EXISTS row_version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.restaurant_tables
    ADD COLUMN IF NOT EXISTS row_version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.table_sessions
    ADD COLUMN IF NOT EXISTS row_version INTEGER NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION public.bump_row_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.row_version := COALESCE(OLD.row_version, 1) + 1;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_row_version ON public.orders;
CREATE TRIGGER trg_orders_row_version
    BEFORE UPDATE ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.bump_row_version();

DROP TRIGGER IF EXISTS trg_order_items_row_version ON public.order_items;
CREATE TRIGGER trg_order_items_row_version
    BEFORE UPDATE ON public.order_items
    FOR EACH ROW
    EXECUTE FUNCTION public.bump_row_version();

DROP TRIGGER IF EXISTS trg_restaurant_tables_row_version ON public.restaurant_tables;
CREATE TRIGGER trg_restaurant_tables_row_version
    BEFORE UPDATE ON public.restaurant_tables
    FOR EACH ROW
    EXECUTE FUNCTION public.bump_row_version();

DROP TRIGGER IF EXISTS trg_table_sessions_row_version ON public.table_sessions;
CREATE TRIGGER trg_table_sessions_row_version
    BEFORE UPDATE ON public.table_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.bump_row_version();

-- ═══════════════════════════════════════════════════════════════════════════
-- B. create_customer_order — validate menu/modifier prices server-side
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_customer_order(
    p_order JSONB,
    p_items JSONB,
    p_modifiers JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order_id UUID := (p_order->>'id')::UUID;
    v_merchant_id UUID := (p_order->>'merchant_id')::UUID;
    v_session_token TEXT := NULLIF(p_order->>'session_token', '');
    v_table_number TEXT := NULLIF(p_order->>'table_number', '');
    v_item JSONB;
    v_modifier JSONB;
    v_menu_item_id TEXT;
    v_menu_price NUMERIC;
    v_menu_name TEXT;
    v_qty INTEGER;
    v_item_id UUID;
    v_mod_id UUID;
    v_mod_price NUMERIC;
    v_expected_unit NUMERIC;
    v_client_unit NUMERIC;
    v_line_mod_sum NUMERIC;
    v_subtotal NUMERIC := 0;
    v_service NUMERIC := COALESCE((p_order->>'service_charge')::NUMERIC, 0);
    v_tax NUMERIC := COALESCE((p_order->>'tax')::NUMERIC, 0);
    v_discount NUMERIC := COALESCE((p_order->>'discount')::NUMERIC, 0);
    v_total NUMERIC := COALESCE((p_order->>'total')::NUMERIC, 0);
    v_client_subtotal NUMERIC := COALESCE((p_order->>'subtotal')::NUMERIC, 0);
BEGIN
    IF v_order_id IS NULL OR v_merchant_id IS NULL OR v_session_token IS NULL OR v_table_number IS NULL THEN
        RAISE EXCEPTION 'invalid customer order identity';
    END IF;

    IF jsonb_array_length(COALESCE(p_items, '[]'::JSONB)) = 0 THEN
        RAISE EXCEPTION 'order must contain at least one item';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM public.table_sessions s
         WHERE s.merchant_id = v_merchant_id
           AND s.table_number = v_table_number
           AND s.session_token = v_session_token
           AND s.is_active = 1
    ) THEN
        RAISE EXCEPTION 'customer order requires the exact active table session';
    END IF;

    -- Idempotent retry of the same order id.
    IF EXISTS (SELECT 1 FROM public.orders WHERE id = v_order_id) THEN
        IF EXISTS (
            SELECT 1 FROM public.orders
             WHERE id = v_order_id
               AND merchant_id = v_merchant_id
               AND session_token = v_session_token
        ) THEN
            RETURN v_order_id;
        END IF;
        RAISE EXCEPTION 'order id is already in use';
    END IF;

    -- Validate every line against live menu + modifier prices; recompute subtotal.
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        v_menu_item_id := NULLIF(v_item->>'item_id', '');
        IF v_menu_item_id IS NULL THEN
            RAISE EXCEPTION 'order item missing item_id';
        END IF;

        SELECT mi.price, mi.name
          INTO v_menu_price, v_menu_name
          FROM public.menu_items mi
         WHERE mi.id = v_menu_item_id
           AND mi.merchant_id = v_merchant_id
           AND COALESCE(mi.is_available, TRUE) = TRUE;

        IF v_menu_price IS NULL THEN
            RAISE EXCEPTION 'menu item % not found or unavailable', v_menu_item_id;
        END IF;

        v_item_id := (v_item->>'id')::UUID;
        v_qty := GREATEST(1, LEAST(COALESCE((v_item->>'quantity')::INTEGER, 1), 99));

        SELECT COALESCE(SUM(m.extra_price), 0)
          INTO v_line_mod_sum
          FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB)) AS elem(value)
          JOIN public.modifiers m
            ON m.id = (elem.value->>'modifier_id')::UUID
           AND m.merchant_id = v_merchant_id
         WHERE (elem.value->>'order_item_id')::UUID = v_item_id;

        FOR v_modifier IN
            SELECT value FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB))
             WHERE (value->>'order_item_id')::UUID = v_item_id
        LOOP
            v_mod_id := (v_modifier->>'modifier_id')::UUID;
            SELECT m.extra_price INTO v_mod_price
              FROM public.modifiers m
             WHERE m.id = v_mod_id
               AND m.merchant_id = v_merchant_id
               AND COALESCE(m.is_available, TRUE) = TRUE
               AND COALESCE(m.is_deleted, FALSE) = FALSE;
            IF v_mod_price IS NULL THEN
                RAISE EXCEPTION 'modifier % not found or unavailable', v_mod_id;
            END IF;
        END LOOP;

        v_expected_unit := v_menu_price + COALESCE(v_line_mod_sum, 0);
        v_client_unit := COALESCE((v_item->>'price')::NUMERIC, -1);
        IF ABS(v_client_unit - v_expected_unit) > 0.05 THEN
            RAISE EXCEPTION 'price mismatch for item %: client %, server %',
                v_menu_item_id, v_client_unit, v_expected_unit;
        END IF;

        v_subtotal := v_subtotal + (v_expected_unit * v_qty);
    END LOOP;

    IF v_discount < 0 OR v_discount > v_subtotal + 0.05 THEN
        RAISE EXCEPTION 'invalid discount % for subtotal %', v_discount, v_subtotal;
    END IF;

    -- Line prices are authoritative. Tax/service/total follow merchant settings
    -- (inclusive/exclusive VAT), so only require the client subtotal to match.
    IF ABS(v_client_subtotal - v_subtotal) > 0.05 THEN
        RAISE EXCEPTION 'subtotal mismatch: client %, server %', v_client_subtotal, v_subtotal;
    END IF;
    IF v_total < 0 OR (v_subtotal > 0 AND v_total + 0.05 < (v_subtotal - v_discount)) THEN
        RAISE EXCEPTION 'invalid total % for subtotal % discount %', v_total, v_subtotal, v_discount;
    END IF;

    INSERT INTO public.orders (
        id, order_number, table_number, total, subtotal, tax, service_charge, discount,
        status, order_source, is_staff_confirmed, session_token, guest_count,
        merchant_id, created_at
    ) VALUES (
        v_order_id,
        p_order->>'order_number',
        v_table_number,
        v_total,
        v_subtotal,
        COALESCE(v_tax, 0),
        COALESCE(v_service, 0),
        COALESCE(v_discount, 0),
        'pending', 'web', FALSE, v_session_token,
        GREATEST(1, LEAST(COALESCE((p_order->>'guest_count')::INTEGER, 1), 100)),
        v_merchant_id,
        COALESCE((p_order->>'created_at')::TIMESTAMPTZ, now())
    );

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        v_item_id := (v_item->>'id')::UUID;
        v_menu_item_id := v_item->>'item_id';
        v_qty := GREATEST(1, LEAST(COALESCE((v_item->>'quantity')::INTEGER, 1), 99));

        SELECT mi.price, mi.name INTO v_menu_price, v_menu_name
          FROM public.menu_items mi
         WHERE mi.id = v_menu_item_id
           AND mi.merchant_id = v_merchant_id;

        SELECT COALESCE(SUM(m.extra_price), 0)
          INTO v_line_mod_sum
          FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB)) AS elem(value)
          JOIN public.modifiers m
            ON m.id = (elem.value->>'modifier_id')::UUID
           AND m.merchant_id = v_merchant_id
         WHERE (elem.value->>'order_item_id')::UUID = v_item_id;

        v_expected_unit := v_menu_price + COALESCE(v_line_mod_sum, 0);

        INSERT INTO public.order_items (
            id, order_id, item_name, quantity, price, status,
            item_id, merchant_id, notes
        ) VALUES (
            v_item_id,
            v_order_id,
            COALESCE(v_menu_name, v_item->>'item_name'),
            v_qty,
            v_expected_unit,
            'pending',
            v_menu_item_id,
            v_merchant_id,
            NULLIF(v_item->>'notes', '')
        );
    END LOOP;

    FOR v_modifier IN SELECT value FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB))
    LOOP
        v_mod_id := (v_modifier->>'modifier_id')::UUID;
        SELECT m.extra_price INTO v_mod_price
          FROM public.modifiers m
         WHERE m.id = v_mod_id
           AND m.merchant_id = v_merchant_id;

        INSERT INTO public.order_item_modifiers (
            id, order_item_id, modifier_id, price, merchant_id
        ) VALUES (
            (v_modifier->>'id')::UUID,
            (v_modifier->>'order_item_id')::UUID,
            v_mod_id,
            COALESCE(v_mod_price, 0),
            v_merchant_id
        );
    END LOOP;

    RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB) TO anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- C. sync_outbox + health RPC
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.sync_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    job_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_sync_outbox_drain
    ON public.sync_outbox (merchant_id, status, next_attempt_at)
    WHERE status IN ('pending', 'failed');

ALTER TABLE public.sync_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sync_outbox_merchant_isolation ON public.sync_outbox;
CREATE POLICY sync_outbox_merchant_isolation ON public.sync_outbox
    FOR ALL
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

GRANT SELECT, INSERT, UPDATE ON public.sync_outbox TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_sync_outbox(
    p_idempotency_key TEXT,
    p_job_type TEXT,
    p_payload JSONB DEFAULT '{}'::JSONB,
    p_merchant_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := COALESCE(p_merchant_id, public.get_active_merchant_id());
    v_id UUID;
BEGIN
    IF v_merchant_id IS NULL OR NULLIF(p_idempotency_key, '') IS NULL OR NULLIF(p_job_type, '') IS NULL THEN
        RAISE EXCEPTION 'invalid outbox enqueue';
    END IF;

    INSERT INTO public.sync_outbox (merchant_id, idempotency_key, job_type, payload)
    VALUES (v_merchant_id, p_idempotency_key, p_job_type, COALESCE(p_payload, '{}'::JSONB))
    ON CONFLICT (merchant_id, idempotency_key) DO UPDATE
        SET updated_at = now()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_sync_outbox(p_limit INTEGER DEFAULT 20)
RETURNS SETOF public.sync_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
BEGIN
    IF v_merchant_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH picked AS (
        SELECT o.id
          FROM public.sync_outbox o
         WHERE o.merchant_id = v_merchant_id
           AND o.status IN ('pending', 'failed')
           AND o.next_attempt_at <= now()
           AND o.attempts < 10
         ORDER BY o.created_at ASC
         LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100))
         FOR UPDATE SKIP LOCKED
    )
    UPDATE public.sync_outbox o
       SET status = 'processing',
           attempts = o.attempts + 1,
           updated_at = now()
      FROM picked
     WHERE o.id = picked.id
    RETURNING o.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_sync_outbox(
    p_id UUID,
    p_success BOOLEAN,
    p_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
BEGIN
    UPDATE public.sync_outbox
       SET status = CASE WHEN p_success THEN 'completed' ELSE 'failed' END,
           last_error = CASE WHEN p_success THEN NULL ELSE LEFT(COALESCE(p_error, 'error'), 500) END,
           next_attempt_at = CASE
               WHEN p_success THEN now()
               ELSE now() + (INTERVAL '30 seconds' * GREATEST(attempts, 1))
           END,
           updated_at = now()
     WHERE id = p_id
       AND merchant_id = v_merchant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_sync_health(
    p_merchant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := COALESCE(p_merchant_id, public.get_active_merchant_id());
    v_pending INT := 0;
    v_failed INT := 0;
    v_processing INT := 0;
    v_oldest TIMESTAMPTZ;
    v_by_type JSONB := '[]'::JSONB;
BEGIN
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error', 'merchant_id required'
        );
    END IF;

    SELECT
        COUNT(*) FILTER (WHERE status = 'pending'),
        COUNT(*) FILTER (WHERE status = 'failed'),
        COUNT(*) FILTER (WHERE status = 'processing'),
        MIN(created_at) FILTER (WHERE status IN ('pending', 'failed', 'processing'))
      INTO v_pending, v_failed, v_processing, v_oldest
      FROM public.sync_outbox
     WHERE merchant_id = v_merchant_id
       AND status IN ('pending', 'failed', 'processing');

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'job_type', job_type,
               'count', cnt
           ) ORDER BY cnt DESC), '[]'::JSONB)
      INTO v_by_type
      FROM (
          SELECT job_type, COUNT(*)::INT AS cnt
            FROM public.sync_outbox
           WHERE merchant_id = v_merchant_id
             AND status IN ('pending', 'failed', 'processing')
           GROUP BY job_type
      ) t;

    RETURN jsonb_build_object(
        'ok', true,
        'merchant_id', v_merchant_id,
        'pending_count', COALESCE(v_pending, 0),
        'failed_count', COALESCE(v_failed, 0),
        'processing_count', COALESCE(v_processing, 0),
        'oldest_created_at', v_oldest,
        'by_job_type', v_by_type,
        'server_time', now()
    );
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_sync_outbox(TEXT, TEXT, JSONB, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_sync_outbox(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_sync_outbox(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_sync_health(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.enqueue_sync_outbox(TEXT, TEXT, JSONB, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_sync_outbox(INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_sync_outbox(UUID, BOOLEAN, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_sync_health(UUID) TO anon, authenticated;

-- Enqueue idempotent outbox rows alongside staff push for new web orders / payments.
CREATE OR REPLACE FUNCTION public.trg_enqueue_web_order_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.order_source = 'web' AND NEW.status = 'pending' THEN
        PERFORM public.enqueue_sync_outbox(
            'web-order:' || NEW.id::TEXT,
            'staff_push',
            jsonb_build_object('order_id', NEW.id, 'table_number', NEW.table_number),
            NEW.merchant_id
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enqueue_web_order_outbox ON public.orders;
CREATE TRIGGER trg_enqueue_web_order_outbox
    AFTER INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_enqueue_web_order_outbox();

CREATE OR REPLACE FUNCTION public.trg_enqueue_payment_print_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.enqueue_sync_outbox(
        'print-receipt:' || NEW.id::TEXT,
        'print_receipt',
        jsonb_build_object(
            'payment_id', NEW.id,
            'order_id', NEW.order_id,
            'amount', NEW.amount
        ),
        NEW.merchant_id
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enqueue_payment_print_outbox ON public.payments;
CREATE TRIGGER trg_enqueue_payment_print_outbox
    AFTER INSERT ON public.payments
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_enqueue_payment_print_outbox();

-- ═══════════════════════════════════════════════════════════════════════════
-- D. Realtime: order_item_modifiers
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime'
           AND schemaname = 'public'
           AND tablename = 'order_item_modifiers'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.order_item_modifiers;
    END IF;
EXCEPTION WHEN undefined_object THEN
    -- Publication may not exist in bare Postgres unit tests; ignore.
    NULL;
END $$;
