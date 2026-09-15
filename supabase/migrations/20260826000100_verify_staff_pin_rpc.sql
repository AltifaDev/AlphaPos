BEGIN;

-- Some installations received credential unification through the canonical
-- Database migration stream before it was mirrored to Supabase migrations.
ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS user_id UUID
    REFERENCES public.users(id) ON DELETE SET NULL;

UPDATE public.employees AS employee
SET user_id = (
    SELECT users.id
    FROM public.users AS users
    WHERE users.merchant_id = employee.merchant_id
      AND lower(btrim(users.username)) = lower(btrim(employee.username))
      AND COALESCE(users.is_deleted, FALSE) = FALSE
    ORDER BY users.updated_at DESC NULLS LAST, users.id DESC
    LIMIT 1
)
WHERE employee.user_id IS NULL;

CREATE INDEX IF NOT EXISTS employees_user_id_idx ON public.employees(user_id);

-- Verify a staff PIN in one server round trip. Credential hashes stay inside
-- PostgreSQL; callers receive only a Boolean result.
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
    v_user_id UUID;
    v_stored_hash TEXT;
    v_iterations INTEGER;
    v_salt TEXT;
    v_expected TEXT;
    v_actual TEXT;
    v_started_at TIMESTAMPTZ;
    v_employee_lookup_ms NUMERIC;
    v_user_lookup_ms NUMERIC;
BEGIN
    IF v_active_merchant IS NULL OR p_employee_id IS NULL THEN
        RETURN FALSE;
    END IF;
    IF p_pin IS NULL OR p_pin !~ '^[0-9]{4}$' THEN
        RETURN FALSE;
    END IF;

    v_started_at := clock_timestamp();
    SELECT e.user_id, e.pin_code
      INTO v_user_id, v_stored_hash
      FROM public.employees e
     WHERE e.id = p_employee_id
       AND e.merchant_id = v_active_merchant
       AND e.resigned_at IS NULL
     LIMIT 1;
    v_employee_lookup_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_started_at)) * 1000;

    IF NOT FOUND THEN
        RAISE LOG 'verify_staff_pin employee_lookup_ms=% user_lookup_ms=0 employee_found=false',
            round(v_employee_lookup_ms, 2);
        RETURN FALSE;
    END IF;

    v_started_at := clock_timestamp();
    IF v_user_id IS NOT NULL THEN
        SELECT u.pin_code_hash
          INTO v_expected
          FROM public.users u
         WHERE u.id = v_user_id
           AND u.merchant_id = v_active_merchant
           AND COALESCE(u.is_deleted, FALSE) = FALSE
           AND COALESCE(u.is_active, TRUE) = TRUE
         LIMIT 1;
        IF v_expected IS NOT NULL AND v_expected <> '' THEN
            v_stored_hash := v_expected;
        END IF;
    END IF;
    v_user_lookup_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_started_at)) * 1000;

    RAISE LOG 'verify_staff_pin employee_lookup_ms=% user_lookup_ms=% employee_found=true user_linked=%',
        round(v_employee_lookup_ms, 2), round(v_user_lookup_ms, 2), (v_user_id IS NOT NULL);

    IF v_stored_hash IS NULL OR v_stored_hash = '' THEN
        RETURN FALSE;
    END IF;

    IF v_stored_hash LIKE 'iter:%' THEN
        IF split_part(v_stored_hash, ':', 2) !~ '^[0-9]+$' THEN
            RETURN FALSE;
        END IF;
        v_iterations := split_part(v_stored_hash, ':', 2)::INTEGER;
        IF v_iterations < 1 OR v_iterations > 100000 THEN
            RETURN FALSE;
        END IF;
        v_salt := split_part(v_stored_hash, ':', 3);
        v_expected := split_part(v_stored_hash, ':', 4);
        v_actual := v_salt || p_pin;
        FOR i IN 1..v_iterations LOOP
            v_actual := encode(digest(convert_to(v_actual, 'UTF8'), 'sha256'), 'hex');
        END LOOP;
        RETURN v_actual = v_expected;
    END IF;

    -- Compatibility with legacy single-round SHA-256 employee credentials.
    v_actual := encode(digest(convert_to(p_pin, 'UTF8'), 'sha256'), 'hex');
    RETURN v_actual = v_stored_hash;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_staff_pin(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_staff_pin(UUID, TEXT) TO anon, authenticated;

COMMIT;
