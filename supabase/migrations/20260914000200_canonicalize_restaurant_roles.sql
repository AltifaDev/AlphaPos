BEGIN;

-- Normalize role names to the international restaurant-role catalog and merge
-- duplicate role UUIDs without changing users' effective permissions.
-- users.role_id remains the authoritative relationship.

CREATE TEMP TABLE alphapos_role_map ON COMMIT DROP AS
WITH canonical_names(alias_name, canonical_name) AS (
    VALUES
        ('manager', 'Restaurant Manager'),
        ('restaurant manager', 'Restaurant Manager'),
        ('store manager', 'Restaurant Manager'),
        ('branch manager', 'Restaurant Manager'),
        ('supervisor', 'Shift Supervisor'),
        ('shift supervisor', 'Shift Supervisor'),
        ('shift lead', 'Shift Supervisor'),
        ('cashier', 'Cashier'),
        ('server', 'Server'),
        ('waiter', 'Server'),
        ('waitress', 'Server'),
        ('waitstaff', 'Server'),
        ('host', 'Host / Hostess'),
        ('hostess', 'Host / Hostess'),
        ('reception', 'Host / Hostess'),
        ('chef', 'Head Chef'),
        ('executive chef', 'Head Chef'),
        ('line cook', 'Cook'),
        ('kitchen staff', 'Cook'),
        ('staff', 'Server')
), classified AS (
    SELECT r.id,
           r.merchant_id,
           r.name,
           COALESCE(c.canonical_name, r.name) AS canonical_name,
           r.updated_at
    FROM public.roles r
    LEFT JOIN canonical_names c ON lower(btrim(r.name)) = c.alias_name
    WHERE COALESCE(r.is_deleted, false) = false
), keepers AS (
    SELECT DISTINCT ON (merchant_id, lower(btrim(canonical_name)))
           merchant_id,
           lower(btrim(canonical_name)) AS canonical_key,
           id AS keeper_id,
           canonical_name
    FROM classified
    ORDER BY merchant_id,
             lower(btrim(canonical_name)),
             (lower(btrim(name)) = lower(btrim(canonical_name))) DESC,
             updated_at DESC NULLS LAST,
             id
)
SELECT c.id AS duplicate_id,
       k.keeper_id,
       k.canonical_name
FROM classified c
JOIN keepers k
  ON k.merchant_id = c.merchant_id
 AND k.canonical_key = lower(btrim(c.canonical_name))
WHERE c.id <> k.keeper_id;

-- Move all accounts first. This preserves the effective permission set while
-- allowing the duplicate role rows to be retired safely.
UPDATE public.users u
SET role_id = m.keeper_id,
    updated_at = NOW()
FROM alphapos_role_map m
WHERE u.role_id = m.duplicate_id;

UPDATE public.roles r
SET is_deleted = true,
    is_synced = false,
    updated_at = NOW()
FROM alphapos_role_map m
WHERE r.id = m.duplicate_id
  AND NOT EXISTS (
      SELECT 1 FROM public.users u WHERE u.role_id = r.id
  );

-- Give the surviving role row the canonical display name. Duplicate rows have
-- already been retired, so this avoids active-name collisions.
UPDATE public.roles r
SET name = m.canonical_name,
    updated_at = NOW()
FROM (
    SELECT DISTINCT keeper_id, canonical_name
    FROM alphapos_role_map
) m
WHERE r.id = m.keeper_id
  AND COALESCE(r.is_deleted, false) = false
  AND r.name <> m.canonical_name;

-- Also normalize a role that had no duplicate and therefore did not appear in
-- alphapos_role_map.
WITH canonical_names(alias_name, canonical_name) AS (
    VALUES
        ('manager', 'Restaurant Manager'),
        ('restaurant manager', 'Restaurant Manager'),
        ('store manager', 'Restaurant Manager'),
        ('branch manager', 'Restaurant Manager'),
        ('supervisor', 'Shift Supervisor'),
        ('shift supervisor', 'Shift Supervisor'),
        ('shift lead', 'Shift Supervisor'),
        ('waiter', 'Server'),
        ('waitress', 'Server'),
        ('waitstaff', 'Server'),
        ('chef', 'Head Chef'),
        ('executive chef', 'Head Chef'),
        ('line cook', 'Cook'),
        ('kitchen staff', 'Cook'),
        ('host', 'Host / Hostess'),
        ('hostess', 'Host / Hostess'),
        ('reception', 'Host / Hostess'),
        ('staff', 'Server')
)
UPDATE public.roles r
SET name = c.canonical_name,
    updated_at = NOW()
FROM canonical_names c
WHERE lower(btrim(r.name)) = c.alias_name
  AND COALESCE(r.is_deleted, false) = false
  AND r.name <> c.canonical_name;

UPDATE public.employees e
SET role = COALESCE(r.name, 'Staff')
FROM public.users u
LEFT JOIN public.roles r ON r.id = u.role_id
WHERE e.user_id = u.id;

COMMIT;
