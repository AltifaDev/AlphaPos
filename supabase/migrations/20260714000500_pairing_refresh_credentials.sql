BEGIN;

ALTER TABLE public.merchant_devices
  ADD COLUMN IF NOT EXISTS refresh_token_hash text,
  ADD COLUMN IF NOT EXISTS refresh_token_expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS idx_device_pairing_tokens_token_unique
  ON public.device_pairing_tokens(token);

DROP FUNCTION IF EXISTS public.consume_device_pairing(text, text, text, text);

CREATE FUNCTION public.consume_device_pairing(
  p_token text,
  p_code text,
  p_device_name text,
  p_device_fingerprint_hash text,
  p_refresh_token_hash text,
  p_refresh_token_expires_at timestamptz
)
RETURNS TABLE(merchant_id uuid, branch_id uuid, device_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
DECLARE
  v_pair public.device_pairing_tokens%ROWTYPE;
  v_device_id uuid := gen_random_uuid();
BEGIN
  IF nullif(trim(p_device_name), '') IS NULL
     OR nullif(trim(p_refresh_token_hash), '') IS NULL
     OR p_refresh_token_expires_at <= now() THEN
    RAISE EXCEPTION 'Invalid device credentials' USING ERRCODE = '22023';
  END IF;

  IF p_token IS NULL AND p_code IS NOT NULL AND (
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
      (p_token IS NOT NULL AND token = p_token)
      OR (p_token IS NULL AND p_code IS NOT NULL AND pairing_code = p_code)
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
    nullif(trim(p_device_fingerprint_hash), ''), v_pair.token, true,
    trim(p_refresh_token_hash), p_refresh_token_expires_at,
    now(), now(), now()
  );

  RETURN QUERY SELECT v_pair.merchant_id, v_pair.branch_id, v_device_id;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_device_pairing(text, text, text, text, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_device_pairing(text, text, text, text, text, timestamptz)
  TO service_role;

COMMIT;
