-- Branch-scoped, synced dining areas replace device-local Floor 1-3 settings.
CREATE TABLE IF NOT EXISTS public.dining_areas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    floor_number INTEGER NOT NULL CHECK (floor_number > 0),
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, branch_id, floor_number)
);

ALTER TABLE public.dining_areas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS merchant_isolation_dining_areas ON public.dining_areas;
CREATE POLICY merchant_isolation_dining_areas ON public.dining_areas
    FOR ALL TO anon, authenticated
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dining_areas TO anon, authenticated;
CREATE INDEX IF NOT EXISTS idx_dining_areas_branch
    ON public.dining_areas (merchant_id, branch_id, sort_order) WHERE NOT is_deleted;

-- Preserve any pre-migration test layouts by materializing their numeric floors
-- as dining areas before replacing numeric references with UUID references.
INSERT INTO public.dining_areas (
    merchant_id, branch_id, floor_number, name, sort_order, is_active, is_deleted
)
SELECT merchant_id, branch_id, floor_number,
       'Floor ' || floor_number::text, floor_number - 1, true, false
FROM (
    SELECT DISTINCT merchant_id, branch_id, floor AS floor_number
    FROM public.restaurant_tables
    WHERE branch_id IS NOT NULL AND floor IS NOT NULL AND NOT coalesce(is_deleted, false)
    UNION
    SELECT DISTINCT merchant_id, branch_id, floor AS floor_number
    FROM public.floor_plan_images
    WHERE branch_id IS NOT NULL AND floor IS NOT NULL AND NOT coalesce(is_deleted, false)
    UNION
    SELECT DISTINCT merchant_id, branch_id, floor AS floor_number
    FROM public.table_layout_presets
    WHERE branch_id IS NOT NULL AND floor IS NOT NULL AND NOT coalesce(is_deleted, false)
) legacy_floors
WHERE floor_number > 0
ON CONFLICT (merchant_id, branch_id, floor_number) DO NOTHING;

ALTER TABLE public.restaurant_tables
    ADD COLUMN IF NOT EXISTS dining_area_id UUID REFERENCES public.dining_areas(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_restaurant_tables_dining_area
    ON public.restaurant_tables (dining_area_id) WHERE NOT is_deleted;

-- Floor plans and reusable layouts belong to a stable dining-area UUID. The
-- legacy numeric floor columns remain nullable only for backwards compatibility.
ALTER TABLE public.floor_plan_images
    ADD COLUMN IF NOT EXISTS dining_area_id UUID REFERENCES public.dining_areas(id) ON DELETE CASCADE;
ALTER TABLE public.table_layout_presets
    ADD COLUMN IF NOT EXISTS dining_area_id UUID REFERENCES public.dining_areas(id) ON DELETE CASCADE;

UPDATE public.floor_plan_images image
SET dining_area_id = area.id
FROM public.dining_areas area
WHERE image.dining_area_id IS NULL
  AND image.merchant_id = area.merchant_id
  AND image.branch_id = area.branch_id
  AND image.floor = area.floor_number;

UPDATE public.table_layout_presets preset
SET dining_area_id = area.id
FROM public.dining_areas area
WHERE preset.dining_area_id IS NULL
  AND preset.merchant_id = area.merchant_id
  AND preset.branch_id = area.branch_id
  AND preset.floor = area.floor_number;

ALTER TABLE public.floor_plan_images ALTER COLUMN floor DROP NOT NULL;
ALTER TABLE public.table_layout_presets ALTER COLUMN floor DROP NOT NULL;

ALTER TABLE public.floor_plan_images
    DROP CONSTRAINT IF EXISTS floor_plan_images_merchant_branch_floor_key;
ALTER TABLE public.floor_plan_images
    ADD CONSTRAINT floor_plan_images_merchant_branch_dining_area_key
    UNIQUE (merchant_id, branch_id, dining_area_id);

DROP INDEX IF EXISTS public.table_layout_presets_scope_name_key;
CREATE UNIQUE INDEX table_layout_presets_scope_name_key
    ON public.table_layout_presets (merchant_id, branch_id, dining_area_id, lower(name))
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_floor_plan_images_dining_area
    ON public.floor_plan_images (dining_area_id);
CREATE INDEX IF NOT EXISTS idx_table_layout_presets_dining_area
    ON public.table_layout_presets (dining_area_id);

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.dining_areas;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
