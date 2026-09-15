-- Migration: Fix allergen_tags and menu_item_allergens RLS for customer web app
-- Allow anon, authenticated, and customer_web to read allergen tags

GRANT SELECT ON public.allergen_tags TO anon, authenticated, customer_web;
GRANT SELECT ON public.menu_item_allergens TO anon, authenticated, customer_web;

DROP POLICY IF EXISTS "merchant_isolation_allergen_tags" ON public.allergen_tags;
CREATE POLICY "merchant_isolation_allergen_tags" ON public.allergen_tags
    FOR SELECT TO anon, authenticated, customer_web
    USING (merchant_id = get_active_merchant_id() OR get_active_merchant_id() IS NULL);

DROP POLICY IF EXISTS "merchant_isolation_menu_item_allergens" ON public.menu_item_allergens;
CREATE POLICY "merchant_isolation_menu_item_allergens" ON public.menu_item_allergens
    FOR SELECT TO anon, authenticated, customer_web
    USING (merchant_id = get_active_merchant_id() OR get_active_merchant_id() IS NULL);
