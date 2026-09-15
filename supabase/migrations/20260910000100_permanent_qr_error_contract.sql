-- Permanent QR reliability contract
-- Expected invalid credentials are returned as data, not database exceptions.
-- Optional audit records must never prevent a valid customer session.

ALTER TABLE public.permanent_qr_access_requests
  ALTER COLUMN service_request_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.request_permanent_qr_access(
  p_merchant_id uuid,
  p_table_number text,
  p_key_hash text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_table public.restaurant_tables%ROWTYPE;
  v_session public.table_sessions%ROWTYPE;
  v_request public.permanent_qr_access_requests%ROWTYPE;
  v_service_id uuid;
  v_clean_table text := trim(p_table_number);
  v_unpadded_table text := ltrim(v_clean_table, '0');
  v_target_hash text := lower(trim(p_key_hash));
BEGIN
  SELECT * INTO v_table
  FROM public.restaurant_tables
  WHERE merchant_id = p_merchant_id
    AND (
      permanent_qr_key_hash = v_target_hash
      OR encode(extensions.digest(convert_to(trim(qr_code_identifier), 'UTF8'), 'sha256'), 'hex') = v_target_hash
    )
    AND permanent_qr_revoked_at IS NULL
    AND is_deleted = false
    AND branch_id IS NOT NULL
    AND (
      table_number = v_clean_table
      OR ltrim(table_number, '0') = v_unpadded_table
      OR lower(table_number) = lower(v_clean_table)
      OR (v_unpadded_table = '' AND ltrim(table_number, '0') = '')
    )
  ORDER BY (table_number = v_clean_table) DESC, updated_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    SELECT * INTO v_table
    FROM public.restaurant_tables
    WHERE merchant_id = p_merchant_id
      AND (
        permanent_qr_key_hash = v_target_hash
        OR encode(extensions.digest(convert_to(trim(qr_code_identifier), 'UTF8'), 'sha256'), 'hex') = v_target_hash
      )
      AND permanent_qr_revoked_at IS NULL
      AND is_deleted = false
      AND branch_id IS NOT NULL
    ORDER BY updated_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  IF v_table.permanent_qr_key_hash IS NULL OR v_table.permanent_qr_key_hash = '' THEN
    UPDATE public.restaurant_tables
    SET permanent_qr_key_hash = v_target_hash
    WHERE id = v_table.id;
  END IF;

  SELECT * INTO v_session
  FROM public.table_sessions
  WHERE merchant_id = v_table.merchant_id
    AND branch_id = v_table.branch_id
    AND table_number = v_table.table_number
    AND is_active = 1
    AND ended_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.table_sessions
      (id, merchant_id, branch_id, table_number, session_token, is_active, guest_count, created_at)
    VALUES
      (gen_random_uuid(), v_table.merchant_id, v_table.branch_id, v_table.table_number,
       'session-' || encode(gen_random_bytes(24), 'hex'), 1, 1, now())
    RETURNING * INTO v_session;
  END IF;

  -- This completed service request is audit metadata. Some imported legacy
  -- tables may not yet have an area, so absence of it must not break ordering.
  IF v_table.dining_area_id IS NOT NULL THEN
    v_service_id := gen_random_uuid();
    INSERT INTO public.service_requests
      (id, merchant_id, branch_id, restaurant_table_id, dining_area_id,
       table_number, request_type, status, created_at, expires_at)
    VALUES
      (v_service_id, v_table.merchant_id, v_table.branch_id, v_table.id,
       v_table.dining_area_id, v_table.table_number,
       'Permanent QR - table active', 'completed', now(), now() + interval '12 hours');
  END IF;

  INSERT INTO public.permanent_qr_access_requests
    (merchant_id, branch_id, restaurant_table_id, table_number,
     service_request_id, status, table_session_id, approved_at, expires_at)
  VALUES
    (v_table.merchant_id, v_table.branch_id, v_table.id, v_table.table_number,
     v_service_id, 'approved', v_session.id, now(), now() + interval '12 hours')
  RETURNING * INTO v_request;

  RETURN jsonb_build_object(
    'request_id', v_request.id,
    'status', 'approved',
    'table_session_id', v_session.id,
    'session_token', v_session.session_token,
    'table_number', v_table.table_number,
    'branch_id', v_table.branch_id,
    'merchant_id', v_table.merchant_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_permanent_qr_access(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_permanent_qr_access(uuid,text,text) TO service_role;

NOTIFY pgrst, 'reload schema';
