-- Explicit Data API privileges after api.auto_expose_new_tables=false.
-- Every tenant table is protected by RLS; only public catalogue reads are
-- available before a merchant JWT is issued.

DO $$
DECLARE
    v_table RECORD;
BEGIN
    FOR v_table IN
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid
        WHERE n.nspname = 'public'
          AND c.relkind = 'r'
          AND a.attname = 'merchant_id'
          AND a.attnum > 0
          AND NOT a.attisdropped
          AND c.relname NOT LIKE '%\_archive' ESCAPE '\'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table.relname);
        EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', v_table.relname);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON public.%I FOR ALL TO public '
            'USING (merchant_id = public.get_active_merchant_id()) '
            'WITH CHECK (merchant_id = public.get_active_merchant_id())',
            v_table.relname
        );
        EXECUTE format(
            'GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO anon, authenticated',
            v_table.relname
        );
    END LOOP;
END;
$$;

ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS merchant_self_access ON public.merchants;
CREATE POLICY merchant_self_access
    ON public.merchants FOR ALL TO public
    USING (id = public.get_active_merchant_id())
    WITH CHECK (id = public.get_active_merchant_id());
GRANT SELECT, UPDATE ON public.merchants TO anon, authenticated;

-- Catalogue data is intentionally public; mutations still require a merchant
-- JWT through the tenant_isolation policy.
DO $$
DECLARE
    v_name TEXT;
BEGIN
    FOREACH v_name IN ARRAY ARRAY[
        'categories',
        'delivery_prices',
        'floor_plan_images',
        'menu_items',
        'menu_item_modifier_groups',
        'modifier_groups',
        'modifiers',
        'promotion_bundle_items',
        'promotions',
        'restaurant_tables',
        'restaurant_walls'
    ]
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS customer_catalog_read ON public.%I', v_name);
        EXECUTE format(
            'CREATE POLICY customer_catalog_read ON public.%I FOR SELECT TO anon USING (true)',
            v_name
        );
    END LOOP;
END;
$$;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

-- Customer checkout can run without a merchant JWT only when the supplied
-- session token belongs to an active table session for that merchant/table.
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
    v_active_merchant UUID := public.get_active_merchant_id();
    v_session_token TEXT := NULLIF(p_order->>'session_token', '');
    v_item JSONB;
    v_modifier JSONB;
BEGIN
    IF v_active_merchant IS DISTINCT FROM v_merchant_id
       AND NOT EXISTS (
           SELECT 1
           FROM public.table_sessions ts
           WHERE ts.merchant_id = v_merchant_id
             AND ts.table_number = p_order->>'table_number'
             AND ts.session_token = v_session_token
             AND ts.is_active = 1
             AND COALESCE(ts.is_deleted, false) = false
       ) THEN
        RAISE EXCEPTION 'merchant authentication or active table session required';
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
        v_session_token,
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

REVOKE ALL ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_customer_order(JSONB, JSONB, JSONB)
    TO anon, authenticated;
