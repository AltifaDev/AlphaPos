-- Reliable customer-order delivery: APNs device registry + atomic order creation.

CREATE TABLE IF NOT EXISTS public.push_devices (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL UNIQUE,
    app_id TEXT NOT NULL CHECK (app_id IN ('pos', 'staff')),
    platform TEXT NOT NULL DEFAULT 'ios',
    is_active BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_devices_merchant_active
    ON public.push_devices (merchant_id, is_active);

ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push_devices_merchant_access" ON public.push_devices;
CREATE POLICY "push_devices_merchant_access"
    ON public.push_devices FOR ALL TO public
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

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

GRANT EXECUTE ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB) TO anon, authenticated;
