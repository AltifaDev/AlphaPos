BEGIN;

ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS user_id UUID
    REFERENCES public.users(id) ON DELETE SET NULL;

-- Keep the most recently updated active account as the canonical login for a
-- merchant/username. Historical duplicates remain as soft-deleted audit rows.
WITH ranked AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY merchant_id, lower(btrim(username))
               ORDER BY updated_at DESC NULLS LAST, id DESC
           ) AS position
    FROM public.users
    WHERE is_deleted = false
)
UPDATE public.users AS users
SET is_deleted = true,
    is_active = false
FROM ranked
WHERE users.id = ranked.id
  AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS users_merchant_username_active_uidx
    ON public.users (merchant_id, lower(btrim(username)))
    WHERE is_deleted = false;

-- Link every Employee to the surviving User account with the same scoped
-- username. This also repairs data produced by pre-038 application builds.
WITH canonical AS (
    SELECT DISTINCT ON (employee.id)
           employee.id AS employee_id,
           users.id AS user_id
    FROM public.employees AS employee
    JOIN public.users AS users
      ON users.merchant_id = employee.merchant_id
     AND lower(btrim(users.username)) = lower(btrim(employee.username))
     AND users.is_deleted = false
    ORDER BY employee.id, users.updated_at DESC NULLS LAST
)
UPDATE public.employees AS employee
SET user_id = canonical.user_id
FROM canonical
WHERE employee.id = canonical.employee_id
  AND employee.user_id IS DISTINCT FROM canonical.user_id;

CREATE INDEX IF NOT EXISTS employees_user_id_idx
    ON public.employees(user_id);

COMMIT;
