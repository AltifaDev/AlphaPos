-- Instant Permanent QR Auto-Session
-- Enables direct customer self-ordering upon scanning table permanent QR code.
-- Automatically creates or reuses active table session without blocking customers on manual staff confirmation.
-- Also ensures permanent_qr_key_hash is automatically populated for all tables.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Auto-compute permanent_qr_key_hash trigger for restaurant_tables
CREATE OR REPLACE FUNCTION public.trg_populate_restaurant_tables_permanent_qr_hash()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.qr_code_identifier IS NOT NULL AND length(trim(NEW.qr_code_identifier)) > 0 THEN
    IF NEW.permanent_qr_key_hash IS NULL OR NEW.permanent_qr_key_hash = '' THEN
      NEW.permanent_qr_key_hash := encode(extensions.digest(convert_to(trim(NEW.qr_code_identifier), 'UTF8'), 'sha256'), 'hex');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_populate_restaurant_tables_permanent_qr_hash ON public.restaurant_tables;
CREATE TRIGGER trg_populate_restaurant_tables_permanent_qr_hash
BEFORE INSERT OR UPDATE OF qr_code_identifier, permanent_qr_key_hash
ON public.restaurant_tables
FOR EACH ROW EXECUTE FUNCTION public.trg_populate_restaurant_tables_permanent_qr_hash();

-- 2. Backfill existing tables where permanent_qr_key_hash is missing
UPDATE public.restaurant_tables
SET permanent_qr_key_hash = encode(extensions.digest(convert_to(trim(qr_code_identifier), 'UTF8'), 'sha256'), 'hex')
WHERE qr_code_identifier IS NOT NULL
  AND length(trim(qr_code_identifier)) > 0
  AND (permanent_qr_key_hash IS NULL OR permanent_qr_key_hash = '');

-- 3. Instant auto-session RPC for permanent QR
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
  -- 1. Locate the restaurant table by merchant + key hash + table number
  -- (with leading zero / padding normalization & dynamic hash calculation fallback)
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

  -- Fallback: If table_number in URL had discrepancy but key_hash matches uniquely for this merchant
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
    RAISE EXCEPTION 'permanent_qr_invalid' USING ERRCODE = '28000';
  END IF;

  -- Ensure permanent_qr_key_hash is set on the table if it was missing
  IF v_table.permanent_qr_key_hash IS NULL OR v_table.permanent_qr_key_hash = '' THEN
    UPDATE public.restaurant_tables
    SET permanent_qr_key_hash = v_target_hash
    WHERE id = v_table.id;
  END IF;

  -- 2. Find existing active session for this table or create a new active session
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

  -- 3. Create service request record if dining_area_id is present (for POS tracking / audit)
  v_service_id := gen_random_uuid();
  IF v_table.dining_area_id IS NOT NULL THEN
    INSERT INTO public.service_requests
      (id, merchant_id, branch_id, restaurant_table_id, dining_area_id,
       table_number, request_type, status, created_at, expires_at)
    VALUES
      (v_service_id, v_table.merchant_id, v_table.branch_id, v_table.id,
       v_table.dining_area_id, v_table.table_number,
       'Permanent QR - table active', 'completed', now(), now() + interval '12 hours')
    ON CONFLICT DO NOTHING;
  END IF;

  -- 4. Record access request as approved
  INSERT INTO public.permanent_qr_access_requests
    (merchant_id, branch_id, restaurant_table_id, table_number,
     service_request_id, status, table_session_id, approved_at, expires_at)
  VALUES
    (v_table.merchant_id, v_table.branch_id, v_table.id, v_table.table_number,
     v_service_id, 'approved', v_session.id, now(), now() + interval '12 hours')
  RETURNING * INTO v_request;

  -- 5. Return approved status immediately with session details
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
