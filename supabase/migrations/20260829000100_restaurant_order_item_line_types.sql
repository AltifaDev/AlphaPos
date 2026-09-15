BEGIN;

ALTER TABLE public.menu_items
    ADD COLUMN IF NOT EXISTS sales_role TEXT NOT NULL DEFAULT 'main',
    ADD COLUMN IF NOT EXISTS sales_role_confirmed BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.menu_items
SET sales_role = 'addon'
WHERE sales_role_confirmed = FALSE
  AND lower(trim(category)) IN ('เพิ่มเติม', 'เพิ่ม', 'addon', 'add-on', 'add on', 'addons', 'extra', 'extras', 'topping', 'toppings');

ALTER TABLE public.menu_items
    DROP CONSTRAINT IF EXISTS menu_items_sales_role_check;
ALTER TABLE public.menu_items
    ADD CONSTRAINT menu_items_sales_role_check CHECK (sales_role IN ('main', 'addon'));

ALTER TABLE public.order_items
    ADD COLUMN IF NOT EXISTS line_type TEXT NOT NULL DEFAULT 'main';

UPDATE public.order_items
SET line_type = CASE
    WHEN notes LIKE '🎁 Promo reward:%' THEN 'promotion_reward'
    WHEN notes LIKE '📦 Bundle component:%' THEN 'bundle_component'
    ELSE 'main'
END
WHERE line_type = 'main';

UPDATE public.order_items oi
SET line_type = 'addon'
FROM public.menu_items mi
WHERE oi.item_id = mi.id
  AND oi.merchant_id = mi.merchant_id
  AND oi.line_type = 'main'
  AND mi.sales_role = 'addon';

ALTER TABLE public.order_items
    DROP CONSTRAINT IF EXISTS order_items_line_type_check;
ALTER TABLE public.order_items
    ADD CONSTRAINT order_items_line_type_check
    CHECK (line_type IN ('main', 'addon', 'bundle_component', 'promotion_reward'));

CREATE OR REPLACE FUNCTION public.apply_menu_sales_role_to_order_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO public
AS $$
DECLARE
  v_sales_role text;
BEGIN
  IF NEW.line_type IS NULL OR NEW.line_type = 'main' THEN
    SELECT sales_role INTO v_sales_role
    FROM public.menu_items
    WHERE id = NEW.item_id AND merchant_id = NEW.merchant_id;
    IF v_sales_role = 'addon' THEN
      NEW.line_type := 'addon';
    ELSE
      NEW.line_type := COALESCE(NEW.line_type, 'main');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_items_apply_menu_sales_role ON public.order_items;
CREATE TRIGGER trg_order_items_apply_menu_sales_role
BEFORE INSERT OR UPDATE OF item_id, line_type ON public.order_items
FOR EACH ROW EXECUTE FUNCTION public.apply_menu_sales_role_to_order_item();

-- The canonical order RPC predates line_type. Keep the atomic write intact,
-- then persist the immutable classification from the same authenticated input
-- before returning row versions to the caller.
CREATE OR REPLACE FUNCTION public.create_order_atomic_cas(
  p_order jsonb,
  p_items jsonb,
  p_modifiers jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_order_id uuid := (p_order->>'id')::uuid;
  v_merchant_id uuid := (p_order->>'merchant_id')::uuid;
  v_expected bigint := NULLIF(p_order->>'expected_row_version', '')::bigint;
  v_actual bigint;
  v_item jsonb;
  v_item_id uuid;
  v_item_expected bigint;
  v_item_actual bigint;
  v_result jsonb;
  v_versions jsonb := '{}'::jsonb;
BEGIN
  IF public.get_active_merchant_id() IS DISTINCT FROM v_merchant_id
     AND NULLIF(p_order->>'session_token', '') IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_order_id
  FROM public.orders
  WHERE merchant_id = v_merchant_id
    AND order_number = NULLIF(trim(p_order->>'order_number'), '')
  LIMIT 1;
  v_order_id := COALESCE(v_order_id, (p_order->>'id')::uuid);

  SELECT row_version INTO v_actual
  FROM public.orders
  WHERE id = v_order_id AND merchant_id = v_merchant_id
  FOR UPDATE;

  IF FOUND AND (v_expected IS NULL OR v_expected <> v_actual) THEN
    RAISE EXCEPTION 'order_conflict id=% expected=% actual=%', v_order_id, v_expected, v_actual
      USING ERRCODE = '40001';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    v_item_id := (v_item->>'id')::uuid;
    v_item_expected := NULLIF(v_item->>'expected_row_version', '')::bigint;
    SELECT row_version INTO v_item_actual
    FROM public.order_items
    WHERE id = v_item_id AND merchant_id = v_merchant_id
    FOR UPDATE;
    IF FOUND AND (v_item_expected IS NULL OR v_item_expected <> v_item_actual) THEN
      RAISE EXCEPTION 'order_item_conflict id=% expected=% actual=%', v_item_id, v_item_expected, v_item_actual
        USING ERRCODE = '40001';
    END IF;
  END LOOP;

  v_result := public.create_order_atomic(p_order, p_items, p_modifiers);

  UPDATE public.order_items oi
  SET line_type = NULLIF(src.value->>'line_type', '')
  FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) AS src(value)
  WHERE oi.id = (src.value->>'id')::uuid
    AND oi.merchant_id = v_merchant_id
    -- Legacy clients and Customer Web may omit line_type. In that case retain
    -- the value already resolved by trg_order_items_apply_menu_sales_role.
    AND NULLIF(src.value->>'line_type', '')
        IN ('main', 'addon', 'bundle_component', 'promotion_reward')
    AND oi.line_type IS DISTINCT FROM NULLIF(src.value->>'line_type', '');

  SELECT row_version INTO v_actual FROM public.orders WHERE id = (v_result->>'order_id')::uuid;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    v_item_id := (v_item->>'id')::uuid;
    SELECT row_version INTO v_item_actual FROM public.order_items WHERE id = v_item_id;
    v_versions := v_versions || jsonb_build_object(lower(v_item_id::text), v_item_actual);
  END LOOP;

  RETURN v_result || jsonb_build_object(
    'order_row_version', v_actual,
    'item_row_versions', v_versions
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb) TO anon, authenticated, service_role;

COMMIT;
