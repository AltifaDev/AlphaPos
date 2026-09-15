-- ==============================================================================
-- Migration: Grant table access for restaurant_walls and floor_plan_images
-- Date: 2026-08-21
-- Purpose: Fix [42501] permission denied for anon/authenticated roles
-- ==============================================================================

-- 1. Grant table access to anon, authenticated, and service_role
GRANT ALL ON public.restaurant_walls TO anon, authenticated, service_role;
GRANT ALL ON public.floor_plan_images TO anon, authenticated, service_role;

-- 2. Ensure RLS is enabled with permissive policies
ALTER TABLE public.restaurant_walls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "restaurant_walls_merchant_access" ON public.restaurant_walls;
CREATE POLICY "restaurant_walls_merchant_access" ON public.restaurant_walls FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE public.floor_plan_images ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "floor_plan_images_merchant_access" ON public.floor_plan_images;
CREATE POLICY "floor_plan_images_merchant_access" ON public.floor_plan_images FOR ALL USING (true) WITH CHECK (true);

-- 3. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
