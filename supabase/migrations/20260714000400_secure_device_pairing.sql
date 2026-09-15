BEGIN;

ALTER TABLE public.merchant_devices
  ADD COLUMN IF NOT EXISTS pairing_token varchar(128);

CREATE UNIQUE INDEX IF NOT EXISTS idx_merchant_devices_pairing_token
  ON public.merchant_devices(pairing_token)
  WHERE pairing_token IS NOT NULL;

DROP POLICY IF EXISTS "pairing_tokens_access_policy" ON public.device_pairing_tokens;
DROP POLICY IF EXISTS "pairing_tokens_insert_policy" ON public.device_pairing_tokens;
CREATE POLICY "pairing_tokens_insert_policy" ON public.device_pairing_tokens
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    merchant_id = public.get_active_merchant_id()
    AND is_used = false
    AND expires_at > now()
    AND expires_at <= now() + interval '15 minutes'
  );

REVOKE ALL ON public.device_pairing_tokens FROM anon, authenticated;
GRANT INSERT ON public.device_pairing_tokens TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.consume_device_pairing(
  p_token text,
  p_code text,
  p_device_name text,
  p_device_fingerprint_hash text
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
  IF nullif(trim(p_device_name), '') IS NULL THEN
    RAISE EXCEPTION 'device_name is required' USING ERRCODE = '22023';
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

  UPDATE public.device_pairing_tokens
  SET is_used = true
  WHERE id = v_pair.id;

  INSERT INTO public.merchant_devices (
    id, merchant_id, branch_id, device_name, device_type,
    device_fingerprint_hash, pairing_token, is_trusted,
    last_seen_at, created_at, updated_at
  ) VALUES (
    v_device_id, v_pair.merchant_id, v_pair.branch_id,
    left(trim(p_device_name), 120), 'staff',
    nullif(trim(p_device_fingerprint_hash), ''), v_pair.token, true,
    now(), now(), now()
  );

  RETURN QUERY SELECT v_pair.merchant_id, v_pair.branch_id, v_device_id;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_device_pairing(text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_device_pairing(text, text, text, text) TO service_role;

COMMIT;
