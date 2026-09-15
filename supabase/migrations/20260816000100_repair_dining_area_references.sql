-- Repair legacy rows that predate branch-scoped dining areas.
-- A branchless floor plan is assigned only when one branch has a unique,
-- strongest table-layout signal for the same merchant and numeric floor.
WITH candidate_counts AS (
    SELECT
        image.id AS image_id,
        area.id AS dining_area_id,
        area.branch_id,
        count(table_row.id) FILTER (WHERE NOT coalesce(table_row.is_deleted, false)) AS table_count
    FROM public.floor_plan_images image
    JOIN public.dining_areas area
      ON area.merchant_id = image.merchant_id
     AND area.floor_number = image.floor
     AND NOT area.is_deleted
    LEFT JOIN public.restaurant_tables table_row
      ON table_row.merchant_id = area.merchant_id
     AND table_row.branch_id = area.branch_id
     AND table_row.floor = area.floor_number
    WHERE image.branch_id IS NULL
      AND image.dining_area_id IS NULL
    GROUP BY image.id, area.id, area.branch_id
), ranked_candidates AS (
    SELECT *,
           dense_rank() OVER (PARTITION BY image_id ORDER BY table_count DESC) AS signal_rank,
           count(*) OVER (PARTITION BY image_id, table_count) AS tied_at_signal
    FROM candidate_counts
), resolved AS (
    SELECT image_id, dining_area_id, branch_id
    FROM ranked_candidates
    WHERE signal_rank = 1 AND tied_at_signal = 1
)
UPDATE public.floor_plan_images image
SET branch_id = resolved.branch_id,
    dining_area_id = resolved.dining_area_id,
    updated_at = now()
FROM resolved
WHERE image.id = resolved.image_id;

-- Backfill every table whose legacy numeric floor has a matching dining area.
UPDATE public.restaurant_tables table_row
SET dining_area_id = area.id
FROM public.dining_areas area
WHERE table_row.dining_area_id IS NULL
  AND table_row.merchant_id = area.merchant_id
  AND table_row.branch_id = area.branch_id
  AND table_row.floor = area.floor_number
  AND NOT area.is_deleted;

-- Floor-plan and preset writes from the current app always carry both UUIDs.
-- Enforce that invariant now that the legacy rows have been repaired.
ALTER TABLE public.floor_plan_images
    ALTER COLUMN branch_id SET NOT NULL,
    ALTER COLUMN dining_area_id SET NOT NULL;

ALTER TABLE public.table_layout_presets
    ALTER COLUMN dining_area_id SET NOT NULL;

NOTIFY pgrst, 'reload schema';
