BEGIN;

-- Employment records are not login accounts. Keep an explicit, auditable
-- entitlement so resigned/HR-only employees never appear on Staff devices.
ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS staff_app_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Preserve existing legitimate deployments: only linked, active accounts with
-- a configured PIN are eligible for the one-time compatibility backfill.
UPDATE public.employees AS employee
SET staff_app_enabled = TRUE
FROM public.users AS account
WHERE employee.user_id = account.id
  AND employee.staff_app_enabled = FALSE
  AND COALESCE(employee.is_deleted, FALSE) = FALSE
  AND employee.resigned_at IS NULL
  AND COALESCE(account.is_deleted, FALSE) = FALSE
  AND COALESCE(account.is_active, TRUE) = TRUE
  AND COALESCE(account.pin_code_hash, '') <> '';

CREATE INDEX IF NOT EXISTS employees_staff_login_scope_idx
    ON public.employees (merchant_id, branch_id, first_name, last_name)
    WHERE staff_app_enabled = TRUE
      AND COALESCE(is_deleted, FALSE) = FALSE
      AND resigned_at IS NULL;

-- Canonical, least-privilege login directory. Credential hashes never leave
-- PostgreSQL. A paired device without a branch claim receives no profiles.
CREATE OR REPLACE FUNCTION public.get_staff_login_profiles()
RETURNS TABLE (
    id UUID,
    first_name TEXT,
    last_name TEXT,
    phone TEXT,
    national_id TEXT,
    employment_type TEXT,
    pay_rate DOUBLE PRECISION,
    username TEXT,
    role TEXT,
    face_registered_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT employee.id,
           employee.first_name::TEXT,
           employee.last_name::TEXT,
           employee.phone::TEXT,
           employee.national_id::TEXT,
           employee.employment_type::TEXT,
           employee.pay_rate::DOUBLE PRECISION,
           account.username::TEXT,
           COALESCE(access_role.name, employee.role, 'Staff')::TEXT,
           employee.face_registered_at
    FROM public.employees AS employee
    JOIN public.users AS account
      ON account.id = employee.user_id
     AND account.merchant_id = employee.merchant_id
    LEFT JOIN public.roles AS access_role
      ON access_role.id = account.role_id
     AND access_role.merchant_id = employee.merchant_id
    WHERE employee.merchant_id = public.get_active_merchant_id()
      AND public.get_active_branch_id() IS NOT NULL
      AND employee.branch_id = public.get_active_branch_id()
      AND employee.staff_app_enabled = TRUE
      AND COALESCE(employee.is_deleted, FALSE) = FALSE
      AND employee.resigned_at IS NULL
      AND COALESCE(account.is_deleted, FALSE) = FALSE
      AND COALESCE(account.is_active, TRUE) = TRUE
      AND COALESCE(account.pin_code_hash, '') <> ''
    ORDER BY employee.first_name, employee.last_name, employee.id;
$$;

REVOKE ALL ON FUNCTION public.get_staff_login_profiles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_staff_login_profiles() TO anon, authenticated;

-- PIN verification enforces the exact same eligibility boundary as the list.
CREATE OR REPLACE FUNCTION public.verify_staff_pin(
    p_employee_id UUID,
    p_pin TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_active_merchant UUID := public.get_active_merchant_id();
    v_active_branch UUID := public.get_active_branch_id();
    v_stored_hash TEXT;
    v_iterations INTEGER;
    v_salt TEXT;
    v_expected TEXT;
    v_actual TEXT;
BEGIN
    IF v_active_merchant IS NULL OR v_active_branch IS NULL OR p_employee_id IS NULL THEN RETURN FALSE; END IF;
    IF p_pin IS NULL OR p_pin !~ '^[0-9]{4}$' THEN RETURN FALSE; END IF;

    SELECT account.pin_code_hash
      INTO v_stored_hash
      FROM public.employees AS employee
      JOIN public.users AS account
        ON account.id = employee.user_id
       AND account.merchant_id = employee.merchant_id
     WHERE employee.id = p_employee_id
       AND employee.merchant_id = v_active_merchant
       AND employee.branch_id = v_active_branch
       AND employee.staff_app_enabled = TRUE
       AND COALESCE(employee.is_deleted, FALSE) = FALSE
       AND employee.resigned_at IS NULL
       AND COALESCE(account.is_deleted, FALSE) = FALSE
       AND COALESCE(account.is_active, TRUE) = TRUE
     LIMIT 1;

    IF NOT FOUND OR COALESCE(v_stored_hash, '') = '' THEN RETURN FALSE; END IF;
    IF v_stored_hash LIKE 'iter:%' THEN
        IF split_part(v_stored_hash, ':', 2) !~ '^[0-9]+$' THEN RETURN FALSE; END IF;
        v_iterations := split_part(v_stored_hash, ':', 2)::INTEGER;
        IF v_iterations < 1 OR v_iterations > 100000 THEN RETURN FALSE; END IF;
        v_salt := split_part(v_stored_hash, ':', 3);
        v_expected := split_part(v_stored_hash, ':', 4);
        v_actual := v_salt || p_pin;
        FOR i IN 1..v_iterations LOOP
            v_actual := encode(digest(convert_to(v_actual, 'UTF8'), 'sha256'), 'hex');
        END LOOP;
        RETURN v_actual = v_expected;
    END IF;
    v_actual := encode(digest(convert_to(p_pin, 'UTF8'), 'sha256'), 'hex');
    RETURN v_actual = v_stored_hash;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_staff_pin(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_staff_pin(UUID, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
