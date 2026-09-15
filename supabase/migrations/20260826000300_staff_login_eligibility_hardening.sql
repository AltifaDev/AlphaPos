BEGIN;

-- Explicit access cannot exist without a canonical account link.
ALTER TABLE public.employees
    DROP CONSTRAINT IF EXISTS employees_staff_app_requires_user;
ALTER TABLE public.employees
    ADD CONSTRAINT employees_staff_app_requires_user
    CHECK (staff_app_enabled = FALSE OR user_id IS NOT NULL);

-- Termination and deletion revoke companion-app access at the data boundary.
-- Re-hiring/re-enabling remains an explicit manager action.
CREATE OR REPLACE FUNCTION public.enforce_staff_app_employee_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(NEW.is_deleted, FALSE) OR NEW.resigned_at IS NOT NULL THEN
        NEW.staff_app_enabled := FALSE;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_staff_app_employee_state ON public.employees;
CREATE TRIGGER trg_enforce_staff_app_employee_state
BEFORE INSERT OR UPDATE OF is_deleted, resigned_at, staff_app_enabled
ON public.employees
FOR EACH ROW EXECUTE FUNCTION public.enforce_staff_app_employee_state();

COMMENT ON COLUMN public.employees.staff_app_enabled IS
    'Explicit branch-scoped authorization for AlphaPosStaff; never inferred from employment alone.';
COMMENT ON FUNCTION public.get_staff_login_profiles() IS
    'Canonical Staff login directory contract v2; returns no credential hashes.';

COMMIT;
