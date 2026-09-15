-- Restore branch-scoped floor metadata from active restaurant tables.
-- `restaurant_tables` is the operational source of truth; dining_areas is
-- required metadata for the iPad floor selector and canvas.

-- A previously soft-deleted area must not hide active tables that still point
-- to it. Keep the UUID stable so floor_plan_images and layout presets remain
-- attached to the same area.
UPDATE public.dining_areas area
SET is_active = true,
    is_deleted = false,
    updated_at = now()
WHERE area.is_deleted = true
  AND EXISTS (
      SELECT 1
      FROM public.restaurant_tables table_row
      WHERE table_row.merchant_id = area.merchant_id
        AND table_row.branch_id = area.branch_id
        AND table_row.dining_area_id = area.id
        AND NOT coalesce(table_row.is_deleted, false)
  );

-- Recreate missing areas from active table rows. This also covers old rows
-- whose dining_area_id is NULL but whose numeric floor is still valid.
INSERT INTO public.dining_areas (
    merchant_id, branch_id, floor_number, name, sort_order,
    is_active, is_deleted, updated_at
)
SELECT table_row.merchant_id,
       table_row.branch_id,
       table_row.floor,
       CASE WHEN table_row.floor = 1 THEN 'Main Area'
            ELSE 'Floor ' || table_row.floor::text END,
       table_row.floor - 1,
       true,
       false,
       now()
FROM public.restaurant_tables table_row
WHERE NOT coalesce(table_row.is_deleted, false)
  AND table_row.branch_id IS NOT NULL
  AND table_row.floor IS NOT NULL
  AND table_row.floor > 0
  AND NOT EXISTS (
      SELECT 1
      FROM public.dining_areas area
      WHERE area.merchant_id = table_row.merchant_id
        AND area.branch_id = table_row.branch_id
        AND area.floor_number = table_row.floor
  )
GROUP BY table_row.merchant_id, table_row.branch_id, table_row.floor
ON CONFLICT (merchant_id, branch_id, floor_number) DO UPDATE
SET is_active = true, is_deleted = false, updated_at = now();

-- Complete the UUID reference for legacy rows. Do not overwrite an existing
-- reference: a valid UUID is more authoritative than the legacy numeric floor.
UPDATE public.restaurant_tables table_row
SET dining_area_id = area.id,
    updated_at = now()
FROM public.dining_areas area
WHERE table_row.dining_area_id IS NULL
  AND NOT coalesce(table_row.is_deleted, false)
  AND table_row.merchant_id = area.merchant_id
  AND table_row.branch_id = area.branch_id
  AND table_row.floor = area.floor_number
  AND area.is_active
  AND NOT area.is_deleted;

NOTIFY pgrst, 'reload schema';
