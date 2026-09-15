-- 6-digit pairing requires POS approval before the device becomes trusted.
-- QR token pairing remains immediate (is_trusted = true).

BEGIN;

DROP FUNCTION IF EXISTS public.consume_device_pairing(text, text, text, text, text, timestamptz);

CREATE FUNCTION public.consume_device_pairing(
  p_token text,
  p_code text,
  p_device_name text,
  p_device_fingerprint_hash text,
  p_refresh_token_hash text,
  p_refresh_token_expires_at timestamptz
)
RETURNS TABLE(
  merchant_id uuid,
  branch_id uuid,
  device_id uuid,
  requires_approval boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
DECLARE
  v_pair public.device_pairing_tokens%ROWTYPE;
  v_device_id uuid := gen_random_uuid();
  v_auto_approve boolean := nullif(trim(coalesce(p_token, '')), '') IS NOT NULL;
BEGIN
  IF nullif(trim(p_device_name), '') IS NULL
     OR nullif(trim(p_refresh_token_hash), '') IS NULL
     OR p_refresh_token_expires_at <= now() THEN
    RAISE EXCEPTION 'Invalid device credentials' USING ERRCODE = '22023';
  END IF;

  IF NOT v_auto_approve AND p_code IS NOT NULL AND (
    SELECT count(*)
    FROM public.device_pairing_tokens
    WHERE pairing_code = p_code AND is_used = false AND expires_at > now()
  ) <> 1 THEN
    RAISE EXCEPTION 'Invalid or ambiguous pairing code' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_pair
  FROM public.device_pairing_tokens
  WHERE is_used = false
    AND expires_at > now()
    AND (
      (v_auto_approve AND token = trim(p_token))
      OR (NOT v_auto_approve AND p_code IS NOT NULL AND pairing_code = p_code)
    )
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired pairing credential' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.device_pairing_tokens SET is_used = true WHERE id = v_pair.id;

  INSERT INTO public.merchant_devices (
    id, merchant_id, branch_id, device_name, device_type,
    device_fingerprint_hash, pairing_token, is_trusted,
    refresh_token_hash, refresh_token_expires_at,
    last_seen_at, created_at, updated_at
  ) VALUES (
    v_device_id, v_pair.merchant_id, v_pair.branch_id,
    left(trim(p_device_name), 120), 'staff',
    nullif(trim(p_device_fingerprint_hash), ''), v_pair.token, v_auto_approve,
    trim(p_refresh_token_hash), p_refresh_token_expires_at,
    now(), now(), now()
  );

  RETURN QUERY
  SELECT v_pair.merchant_id, v_pair.branch_id, v_device_id, NOT v_auto_approve;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_device_pairing(text, text, text, text, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_device_pairing(text, text, text, text, text, timestamptz)
  TO service_role;

CREATE OR REPLACE FUNCTION public.approve_pending_device_pairing(p_device_id uuid)
RETURNS TABLE(
  device_id uuid,
  device_name text,
  is_trusted boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_merchant uuid := public.get_active_merchant_id();
BEGIN
  IF p_device_id IS NULL OR v_merchant IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  UPDATE public.merchant_devices d
  SET is_trusted = true,
      updated_at = now(),
      last_seen_at = now()
  WHERE d.id = p_device_id
    AND d.merchant_id = v_merchant
    AND d.is_trusted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No pending device to approve' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT d.id, d.device_name, d.is_trusted
  FROM public.merchant_devices d
  WHERE d.id = p_device_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_pending_device_pairing(p_device_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_merchant uuid := public.get_active_merchant_id();
  v_deleted int := 0;
BEGIN
  IF p_device_id IS NULL OR v_merchant IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.merchant_devices d
  WHERE d.id = p_device_id
    AND d.merchant_id = v_merchant
    AND d.is_trusted = false;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted = 0 THEN
    RAISE EXCEPTION 'No pending device to reject' USING ERRCODE = 'P0002';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_pending_device_pairing(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_pending_device_pairing(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_pending_device_pairing(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reject_pending_device_pairing(uuid) TO anon, authenticated, service_role;

COMMIT;
