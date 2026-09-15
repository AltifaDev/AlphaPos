-- Permanent table QR flow. A permanent QR identifies a table but never grants
-- ordering authority by itself: staff must resolve its service request first.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

ALTER TABLE public.restaurant_tables
  ADD COLUMN IF NOT EXISTS permanent_qr_key_hash text,
  ADD COLUMN IF NOT EXISTS permanent_qr_version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS permanent_qr_revoked_at timestamptz;

-- Existing identifiers were already generated as opaque UUID-bearing values by
-- AlphaPos. Replace missing/legacy-short identifiers before hashing them.
UPDATE public.restaurant_tables
SET qr_code_identifier = 'table_' || gen_random_uuid()::text,
    updated_at = now()
WHERE qr_code_identifier IS NULL OR length(trim(qr_code_identifier)) < 24;

UPDATE public.restaurant_tables
SET permanent_qr_key_hash = encode(
      extensions.digest(convert_to(qr_code_identifier, 'UTF8'), 'sha256'),
      'hex'
    )
WHERE permanent_qr_key_hash IS NULL
  AND qr_code_identifier IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_restaurant_tables_permanent_qr_hash
  ON public.restaurant_tables (permanent_qr_key_hash)
  WHERE permanent_qr_revoked_at IS NULL AND is_deleted = false;

CREATE TABLE IF NOT EXISTS public.permanent_qr_access_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  restaurant_table_id uuid NOT NULL REFERENCES public.restaurant_tables(id) ON DELETE CASCADE,
  table_number varchar(50) NOT NULL,
  service_request_id uuid NOT NULL UNIQUE REFERENCES public.service_requests(id) ON DELETE CASCADE,
  status varchar(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','expired')),
  table_session_id uuid REFERENCES public.table_sessions(id) ON DELETE SET NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '5 minutes'),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_permanent_qr_one_pending_per_table
  ON public.permanent_qr_access_requests (restaurant_table_id)
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_permanent_qr_requests_scope
  ON public.permanent_qr_access_requests (merchant_id, branch_id, status, requested_at DESC);

ALTER TABLE public.permanent_qr_access_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.permanent_qr_access_requests FROM anon, authenticated, customer_web;

-- Called by the service-role Edge Function. It deduplicates repeated scans and
-- creates the existing cross-app service-request notification.
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
  v_request public.permanent_qr_access_requests%ROWTYPE;
  v_service_id uuid;
BEGIN
  SELECT * INTO v_table
  FROM public.restaurant_tables
  WHERE merchant_id = p_merchant_id
    AND table_number = p_table_number
    AND permanent_qr_key_hash = lower(p_key_hash)
    AND permanent_qr_revoked_at IS NULL
    AND is_deleted = false
    AND branch_id IS NOT NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'permanent_qr_invalid' USING ERRCODE = '28000';
  END IF;

  UPDATE public.permanent_qr_access_requests
  SET status = 'expired', updated_at = now()
  WHERE restaurant_table_id = v_table.id
    AND status = 'pending' AND expires_at <= now();

  SELECT * INTO v_request
  FROM public.permanent_qr_access_requests
  WHERE restaurant_table_id = v_table.id AND status = 'pending'
  ORDER BY requested_at DESC LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('request_id', v_request.id, 'status', 'pending',
      'expires_at', v_request.expires_at, 'table_number', v_table.table_number);
  END IF;

  v_service_id := gen_random_uuid();
  INSERT INTO public.service_requests
    (id, merchant_id, branch_id, table_number, request_type, status, created_at)
  VALUES
    (v_service_id, v_table.merchant_id, v_table.branch_id, v_table.table_number,
     'Permanent QR - confirm table', 'pending', now());

  INSERT INTO public.permanent_qr_access_requests
    (merchant_id, branch_id, restaurant_table_id, table_number, service_request_id)
  VALUES
    (v_table.merchant_id, v_table.branch_id, v_table.id, v_table.table_number, v_service_id)
  RETURNING * INTO v_request;

  RETURN jsonb_build_object('request_id', v_request.id, 'status', 'pending',
    'expires_at', v_request.expires_at, 'table_number', v_table.table_number);
END;
$$;

REVOKE ALL ON FUNCTION public.request_permanent_qr_access(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_permanent_qr_access(uuid,text,text) TO service_role;

-- Resolving the familiar service request is the explicit staff approval. The
-- trigger creates/reuses the active session and commits approval atomically.
CREATE OR REPLACE FUNCTION public.approve_permanent_qr_from_service_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_access public.permanent_qr_access_requests%ROWTYPE;
  v_session public.table_sessions%ROWTYPE;
BEGIN
  IF NEW.status <> 'completed' OR OLD.status = 'completed' THEN RETURN NEW; END IF;

  SELECT * INTO v_access
  FROM public.permanent_qr_access_requests
  WHERE service_request_id = NEW.id AND status = 'pending'
  FOR UPDATE;
  IF NOT FOUND THEN RETURN NEW; END IF;

  IF v_access.expires_at <= now() THEN
    UPDATE public.permanent_qr_access_requests
    SET status='expired', updated_at=now() WHERE id=v_access.id;
    RETURN NEW;
  END IF;

  SELECT * INTO v_session
  FROM public.table_sessions
  WHERE merchant_id=v_access.merchant_id AND branch_id=v_access.branch_id
    AND table_number=v_access.table_number AND is_active=1 AND ended_at IS NULL
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.table_sessions
      (id, merchant_id, branch_id, table_number, session_token, is_active, guest_count, created_at)
    VALUES
      (gen_random_uuid(), v_access.merchant_id, v_access.branch_id, v_access.table_number,
       'session-' || encode(gen_random_bytes(24), 'hex'), 1, 1, now())
    RETURNING * INTO v_session;
  END IF;

  UPDATE public.permanent_qr_access_requests
  SET status='approved', table_session_id=v_session.id,
      approved_at=now(), updated_at=now()
  WHERE id=v_access.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_approve_permanent_qr_from_service_request ON public.service_requests;
CREATE TRIGGER trg_approve_permanent_qr_from_service_request
AFTER UPDATE OF status ON public.service_requests
FOR EACH ROW EXECUTE FUNCTION public.approve_permanent_qr_from_service_request();

