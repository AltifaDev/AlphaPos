-- Secure pairing-code creation for POS (merchant JWT / anon role).
-- Direct table INSERT only had INSERT privilege; PostgREST Prefer:
-- resolution=merge-duplicates effectively needs SELECT+UPDATE as well.
-- Create via SECURITY DEFINER RPC instead of broadening table grants.

BEGIN;

CREATE OR REPLACE FUNCTION public.create_device_pairing(
  p_merchant_id uuid,
  p_branch_id uuid
)
RETURNS TABLE(
  id uuid,
  merchant_id uuid,
  branch_id uuid,
  token text,
  pairing_code text,
  expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_active uuid := public.get_active_merchant_id();
  v_id uuid := gen_random_uuid();
  v_token text;
  v_code text;
  v_expires timestamptz := now() + interval '10 minutes';
  v_attempt int := 0;
BEGIN
  IF p_merchant_id IS NULL OR p_branch_id IS NULL THEN
    RAISE EXCEPTION 'merchant_id and branch_id are required' USING ERRCODE = '22023';
  END IF;

  IF v_active IS NULL OR p_merchant_id IS DISTINCT FROM v_active THEN
    RAISE EXCEPTION 'merchant mismatch' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.merchant_id = p_merchant_id
  ) THEN
    RAISE EXCEPTION 'branch does not belong to merchant' USING ERRCODE = '22023';
  END IF;

  v_token := replace(gen_random_uuid()::text || '-' || gen_random_uuid()::text, '-', '');

  LOOP
    v_attempt := v_attempt + 1;
    IF v_attempt > 25 THEN
      RAISE EXCEPTION 'unable to allocate pairing code' USING ERRCODE = 'P0001';
    END IF;

    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM public.device_pairing_tokens t
      WHERE t.pairing_code = v_code
        AND t.is_used = false
        AND t.expires_at > now()
    );
  END LOOP;

  INSERT INTO public.device_pairing_tokens (
    id, merchant_id, branch_id, token, pairing_code, expires_at, is_used, created_at
  ) VALUES (
    v_id, p_merchant_id, p_branch_id, v_token, v_code, v_expires, false, now()
  );

  RETURN QUERY
  SELECT v_id, p_merchant_id, p_branch_id, v_token, v_code, v_expires;
END;
$$;

REVOKE ALL ON FUNCTION public.create_device_pairing(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_device_pairing(uuid, uuid) TO anon, authenticated, service_role;

-- Pairing rows are created only through the RPC above.
DROP POLICY IF EXISTS "pairing_tokens_insert_policy" ON public.device_pairing_tokens;
REVOKE ALL ON public.device_pairing_tokens FROM anon, authenticated;

COMMIT;
