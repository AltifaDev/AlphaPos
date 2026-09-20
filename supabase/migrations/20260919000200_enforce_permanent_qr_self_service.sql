-- Permanent table QR self-service contract
--
-- A permanent QR identifies a table; it must never identify a bill/session.
-- Every scan may therefore reuse the current active session or create a new
-- session after the previous one was closed. No staff approval is required.

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
  v_clean_table text := trim(coalesce(p_table_number, ''));
  v_unpadded_table text := ltrim(v_clean_table, '0');
  v_target_hash text := lower(trim(coalesce(p_key_hash, '')));
BEGIN
  -- Lock the table row first. This serializes two customers scanning the same
  -- QR at the same time and prevents duplicate active sessions.
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
    )
  ORDER BY (table_number = v_clean_table) DESC, updated_at DESC
  LIMIT 1
  FOR UPDATE;

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
      (id, merchant_id, branch_id, table_number, session_token,
       is_active, guest_count, created_at)
    VALUES
      (gen_random_uuid(), v_table.merchant_id, v_table.branch_id,
       v_table.table_number, 'session-' || encode(gen_random_bytes(24), 'hex'),
       1, 1, now())
    RETURNING * INTO v_session;
  END IF;

  -- Keep the audit record, but mark it approved immediately. It is not an
  -- approval workflow and must never block ordering.
  INSERT INTO public.permanent_qr_access_requests
    (merchant_id, branch_id, restaurant_table_id, table_number,
     service_request_id, status, table_session_id, approved_at, expires_at)
  VALUES
    (v_table.merchant_id, v_table.branch_id, v_table.id, v_table.table_number,
     NULL, 'approved', v_session.id, now(), now() + interval '12 hours');

  RETURN jsonb_build_object(
    'status', 'approved',
    'table_session_id', v_session.id,
    'session_token', v_session.session_token,
    'table_number', v_table.table_number,
    'branch_id', v_table.branch_id,
    'merchant_id', v_table.merchant_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_permanent_qr_access(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_permanent_qr_access(uuid, text, text) TO service_role;

NOTIFY pgrst, 'reload schema';
