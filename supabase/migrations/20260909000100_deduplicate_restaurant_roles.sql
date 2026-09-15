-- Prevent duplicate active role names for one merchant.
-- Existing users are reassigned to the most recently used canonical row before
-- duplicate rows are soft-deleted, so historical references remain recoverable.

BEGIN;

WITH ranked AS (
    SELECT
        r.id,
        first_value(r.id) OVER (
            PARTITION BY r.merchant_id, lower(btrim(r.name))
            ORDER BY
                (SELECT count(*) FROM public.users u WHERE u.role_id = r.id) DESC,
                r.updated_at DESC,
                r.id
        ) AS keeper_id,
        row_number() OVER (
            PARTITION BY r.merchant_id, lower(btrim(r.name))
            ORDER BY
                (SELECT count(*) FROM public.users u WHERE u.role_id = r.id) DESC,
                r.updated_at DESC,
                r.id
        ) AS duplicate_rank
    FROM public.roles r
    WHERE r.is_deleted = FALSE
), duplicates AS (
    SELECT id, keeper_id FROM ranked WHERE duplicate_rank > 1
)
UPDATE public.users u
SET role_id = d.keeper_id,
    is_synced = FALSE,
    updated_at = now()
FROM duplicates d
WHERE u.role_id = d.id;

WITH ranked AS (
    SELECT
        r.id,
        row_number() OVER (
            PARTITION BY r.merchant_id, lower(btrim(r.name))
            ORDER BY
                (SELECT count(*) FROM public.users u WHERE u.role_id = r.id) DESC,
                r.updated_at DESC,
                r.id
        ) AS duplicate_rank
    FROM public.roles r
    WHERE r.is_deleted = FALSE
)
UPDATE public.roles r
SET is_deleted = TRUE,
    is_synced = TRUE,
    updated_at = now()
FROM ranked x
WHERE r.id = x.id
  AND x.duplicate_rank > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_roles_merchant_active_normalized_name
    ON public.roles (merchant_id, lower(btrim(name)))
    WHERE is_deleted = FALSE;

COMMIT;
