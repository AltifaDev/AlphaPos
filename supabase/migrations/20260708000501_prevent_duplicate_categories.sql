-- Keep category names unique per merchant. This prevents startup cleanup loops
-- caused by the same category being seeded or pulled under different UUIDs.

WITH ranked_categories AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id, lower(btrim(name))
            ORDER BY is_deleted ASC, updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
        ) AS keep_rank
    FROM public.categories
)
UPDATE public.categories c
SET is_deleted = true,
    updated_at = now()
FROM ranked_categories ranked
WHERE c.id = ranked.id
  AND ranked.keep_rank > 1
  AND COALESCE(c.is_deleted, false) = false;

CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_unique_active_name_per_merchant
    ON public.categories (merchant_id, lower(btrim(name)))
    WHERE is_deleted = false;
