BEGIN;

CREATE OR REPLACE FUNCTION public.upsert_table_session_cas(p_session jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
SET statement_timeout TO '5s'
SET lock_timeout TO '2s'
AS $$
DECLARE
  v_id uuid := (p_session->>'id')::uuid;
  v_merchant uuid := (p_session->>'merchant_id')::uuid;
  v_expected bigint := NULLIF(p_session->>'expected_row_version','')::bigint;
  v_actual bigint;
BEGIN
  IF public.get_active_merchant_id() IS DISTINCT FROM v_merchant THEN
    RAISE EXCEPTION 'merchant_scope_mismatch' USING ERRCODE='42501';
  END IF;

  -- Resolve retries by the unique business token before locking.
  SELECT id INTO v_id FROM public.table_sessions
   WHERE merchant_id=v_merchant AND session_token=p_session->>'session_token' LIMIT 1;
  v_id := COALESCE(v_id,(p_session->>'id')::uuid);

  SELECT row_version INTO v_actual FROM public.table_sessions
   WHERE id=v_id AND merchant_id=v_merchant FOR UPDATE;
  IF FOUND AND (v_expected IS NULL OR v_expected <> v_actual) THEN
    RAISE EXCEPTION 'table_session_conflict id=% expected=% actual=%',v_id,v_expected,v_actual
      USING ERRCODE='40001';
  END IF;

  INSERT INTO public.table_sessions (
    id, merchant_id, branch_id, table_number, session_token, is_active,
    guest_count, cashier_name, started_at, created_at, ended_at, updated_at
  ) VALUES (
    v_id, v_merchant, NULLIF(p_session->>'branch_id','')::uuid,
    p_session->>'table_number', p_session->>'session_token',
    COALESCE((p_session->>'is_active')::int,1),
    COALESCE((p_session->>'guest_count')::int,2), COALESCE(p_session->>'cashier_name',''),
    COALESCE((p_session->>'created_at')::timestamptz,now()),
    COALESCE((p_session->>'created_at')::timestamptz,now()),
    NULLIF(p_session->>'ended_at','')::timestamptz, now()
  ) ON CONFLICT (id) DO UPDATE SET
    branch_id=EXCLUDED.branch_id, table_number=EXCLUDED.table_number,
    is_active=EXCLUDED.is_active, guest_count=EXCLUDED.guest_count,
    cashier_name=EXCLUDED.cashier_name, ended_at=EXCLUDED.ended_at;

  SELECT row_version INTO v_actual FROM public.table_sessions WHERE id=v_id;
  RETURN jsonb_build_object('id',v_id,'row_version',v_actual);
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_table_session_cas(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_table_session_cas(jsonb) TO anon, authenticated, service_role;

COMMIT;
