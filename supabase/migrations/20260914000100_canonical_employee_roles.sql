BEGIN;

-- users.role_id is the only authoritative access-role reference.
-- employees.role remains a compatibility mirror for legacy clients.

UPDATE public.users AS u
SET role_id = r.id,
    updated_at = NOW()
FROM public.employees AS e
JOIN public.roles AS r
  ON r.merchant_id = e.merchant_id
 AND lower(btrim(r.name)) = lower(btrim(e.role))
 AND COALESCE(r.is_deleted, FALSE) = FALSE
WHERE e.user_id = u.id
  AND u.role_id IS NULL
  AND COALESCE(u.is_deleted, FALSE) = FALSE;

CREATE OR REPLACE FUNCTION public.sync_employee_legacy_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.role_id IS NOT DISTINCT FROM NEW.role_id THEN
        RETURN NEW;
    END IF;

    UPDATE public.employees AS e
    SET role = COALESCE(r.name, 'Staff')
    FROM public.roles AS r
    WHERE e.user_id = NEW.id
      AND r.id = NEW.role_id
      AND r.merchant_id = NEW.merchant_id;

    IF NEW.role_id IS NULL THEN
        UPDATE public.employees
        SET role = 'Staff'
        WHERE user_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_employee_legacy_role ON public.users;

CREATE TRIGGER trg_sync_employee_legacy_role
AFTER INSERT OR UPDATE OF role_id ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.sync_employee_legacy_role();

-- Normalize the compatibility mirror for all linked employees.
UPDATE public.employees AS e
SET role = COALESCE(r.name, 'Staff')
FROM public.users AS u
LEFT JOIN public.roles AS r
  ON r.id = u.role_id
 AND r.merchant_id = u.merchant_id
WHERE e.user_id = u.id;

COMMIT;
