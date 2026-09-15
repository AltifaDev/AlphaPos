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
    SELECT sales_role INTO v_sales_role FROM public.menu_items
    WHERE id = NEW.item_id AND merchant_id = NEW.merchant_id;
    NEW.line_type := CASE WHEN v_sales_role = 'addon' THEN 'addon' ELSE COALESCE(NEW.line_type, 'main') END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_items_apply_menu_sales_role ON public.order_items;
CREATE TRIGGER trg_order_items_apply_menu_sales_role
BEFORE INSERT OR UPDATE OF item_id, line_type ON public.order_items
FOR EACH ROW EXECUTE FUNCTION public.apply_menu_sales_role_to_order_item();

COMMIT;
