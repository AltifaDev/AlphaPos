-- One database contract for customer order creation and staff approval.

DROP TRIGGER IF EXISTS trg_normalize_web_order_status ON public.orders;
DROP FUNCTION IF EXISTS public.trg_normalize_web_order_status();

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
    v_total NUMERIC := COALESCE((p_order->>'total')::NUMERIC, 0);
    v_item JSONB;
    v_modifier JSONB;
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

    -- A response can be lost after commit. Retrying the same order id is safe.
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

    INSERT INTO public.orders (
        id, order_number, table_number, total, subtotal, tax, service_charge, discount,
        status, order_source, is_staff_confirmed, session_token, guest_count,
        merchant_id, created_at
    ) VALUES (
        v_order_id,
        p_order->>'order_number',
        v_table_number,
        v_total,
        COALESCE(NULLIF((p_order->>'subtotal')::NUMERIC, 0), v_total),
        COALESCE((p_order->>'tax')::NUMERIC, 0),
        COALESCE((p_order->>'service_charge')::NUMERIC, 0),
        COALESCE((p_order->>'discount')::NUMERIC, 0),
        'pending', 'web', FALSE, v_session_token,
        GREATEST(1, LEAST(COALESCE((p_order->>'guest_count')::INTEGER, 1), 100)),
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
            GREATEST(1, LEAST((v_item->>'quantity')::INTEGER, 99)),
            (v_item->>'price')::NUMERIC,
            'pending',
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

CREATE OR REPLACE FUNCTION public.approve_customer_order(p_order_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
BEGIN
    IF v_merchant_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.orders
         WHERE id = p_order_id
           AND merchant_id = v_merchant_id
           AND order_source = 'web'
           AND is_deleted = FALSE
    ) THEN
        RAISE EXCEPTION 'customer order not found for active merchant';
    END IF;

    UPDATE public.orders
       SET status = 'preparing', is_staff_confirmed = TRUE, updated_at = now()
     WHERE id = p_order_id
       AND merchant_id = v_merchant_id;

    UPDATE public.order_items
       SET status = 'cooking', updated_at = now()
     WHERE order_id = p_order_id
       AND merchant_id = v_merchant_id
       AND status = 'pending'
       AND is_deleted = FALSE;

    RETURN p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_customer_order(UUID) FROM PUBLIC;
-- NOTE: The staff/iPad apps authenticate with the merchant JWT issued by the
-- `issue-merchant-token` Edge Function, whose Postgres role is `anon`
-- (not `authenticated`). Tenant isolation is enforced inside the functions via
-- get_active_merchant_id() (read from the JWT `merchant_id` claim) plus the
-- order_source / is_deleted guards below, so `anon` must keep EXECUTE here —
-- otherwise rpc/approve_customer_order returns "permission denied" and the
-- staff approve button does nothing.
GRANT EXECUTE ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_customer_order(UUID) TO anon, authenticated;

-- Browsers may create orders only through the validated transaction above.
REVOKE INSERT, UPDATE, DELETE ON public.orders, public.order_items, public.order_item_modifiers FROM anon;
