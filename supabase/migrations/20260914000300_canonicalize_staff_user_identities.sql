BEGIN;

SELECT pg_advisory_xact_lock(hashtext('alphapos:canonicalize_staff_user_identities'));

-- Choose the User already referenced by an active Employee whenever possible.
-- This preserves the account whose PIN is used by the employee and avoids
-- silently moving credentials to a newer duplicate row.
CREATE TEMP TABLE alphapos_user_map ON COMMIT DROP AS
WITH ranked AS (
    SELECT u.id,
           u.merchant_id,
           lower(btrim(u.username)) AS username_key,
           EXISTS (
               SELECT 1 FROM public.employees e
               WHERE e.user_id = u.id
                 AND COALESCE(e.is_deleted, false) = false
           ) AS is_employee_linked,
           row_number() OVER (
               PARTITION BY u.merchant_id, lower(btrim(u.username))
               ORDER BY EXISTS (
                   SELECT 1 FROM public.employees e
                   WHERE e.user_id = u.id
                     AND COALESCE(e.is_deleted, false) = false
               ) DESC,
               u.updated_at DESC NULLS LAST,
               u.id
           ) AS position
    FROM public.users u
    WHERE COALESCE(u.is_deleted, false) = false
)
SELECT duplicate.id AS duplicate_id,
       keeper.id AS keeper_id
FROM ranked duplicate
JOIN ranked keeper
  ON keeper.merchant_id = duplicate.merchant_id
 AND keeper.username_key = duplicate.username_key
 AND keeper.position = 1
WHERE duplicate.position > 1;

UPDATE public.employees e
SET user_id = m.keeper_id,
    updated_at = NOW()
FROM alphapos_user_map m
WHERE e.user_id = m.duplicate_id;

UPDATE public.users u
SET is_deleted = true,
    is_active = false,
    updated_at = NOW()
FROM alphapos_user_map m
WHERE u.id = m.duplicate_id;

-- Repair legacy employees that have a username but no User relationship.
UPDATE public.employees e
SET user_id = u.id,
    updated_at = NOW()
FROM public.users u
WHERE e.user_id IS NULL
  AND COALESCE(e.is_deleted, false) = false
  AND COALESCE(u.is_deleted, false) = false
  AND u.merchant_id = e.merchant_id
  AND lower(btrim(u.username)) = lower(btrim(e.username));

CREATE UNIQUE INDEX IF NOT EXISTS users_merchant_username_active_uidx
    ON public.users (merchant_id, lower(btrim(username)))
    WHERE is_deleted = false;

UPDATE public.employees e
SET role = COALESCE(r.name, 'Staff')
FROM public.users u
LEFT JOIN public.roles r ON r.id = u.role_id
WHERE e.user_id = u.id;

COMMIT;
