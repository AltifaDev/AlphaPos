-- Keep the operational service-request queue consistent with the table plan.
-- Permanent-QR approvals are short-lived and must not survive their access request.

ALTER TABLE public.service_requests
  ADD COLUMN IF NOT EXISTS restaurant_table_id uuid REFERENCES public.restaurant_tables(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS dining_area_id uuid REFERENCES public.dining_areas(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_service_requests_active_scope
  ON public.service_requests (merchant_id, branch_id, dining_area_id, status, created_at DESC);

-- Recover the exact table/area/expiry for existing permanent-QR requests.
UPDATE public.service_requests sr
SET restaurant_table_id = ar.restaurant_table_id,
    dining_area_id = rt.dining_area_id,
    expires_at = ar.expires_at
FROM public.permanent_qr_access_requests ar
JOIN public.restaurant_tables rt ON rt.id = ar.restaurant_table_id
WHERE ar.service_request_id = sr.id
  AND sr.request_type = 'Permanent QR - confirm table';

-- Close stale queue rows. Previously only the access row expired, leaving the
-- service request visible forever and allowing a second visible request.
UPDATE public.service_requests
SET status = 'expired'
WHERE request_type = 'Permanent QR - confirm table'
  AND status = 'pending'
  AND expires_at IS NOT NULL
  AND expires_at <= now();

-- Defensive cleanup before enforcing one live permanent-QR request per table.
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY restaurant_table_id
           ORDER BY created_at DESC, id DESC
         ) AS position
  FROM public.service_requests
  WHERE request_type = 'Permanent QR - confirm table'
    AND status = 'pending'
    AND restaurant_table_id IS NOT NULL
)
UPDATE public.service_requests sr
SET status = 'expired'
FROM ranked r
WHERE sr.id = r.id AND r.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_service_requests_one_pending_permanent_qr
  ON public.service_requests (restaurant_table_id)
  WHERE request_type = 'Permanent QR - confirm table'
    AND status = 'pending'
    AND restaurant_table_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.enforce_service_request_table_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_table public.restaurant_tables%ROWTYPE;
BEGIN
  SELECT * INTO v_table
  FROM public.restaurant_tables
  WHERE merchant_id = NEW.merchant_id
    AND branch_id = NEW.branch_id
    AND table_number = NEW.table_number
    AND is_deleted = false
  ORDER BY updated_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'service_request_table_not_found';
  END IF;

  NEW.restaurant_table_id := v_table.id;
  NEW.dining_area_id := v_table.dining_area_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_service_request_table_scope ON public.service_requests;
CREATE TRIGGER trg_enforce_service_request_table_scope
BEFORE INSERT OR UPDATE OF merchant_id, branch_id, table_number
ON public.service_requests
FOR EACH ROW EXECUTE FUNCTION public.enforce_service_request_table_scope();

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
    AND dining_area_id IS NOT NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'permanent_qr_invalid' USING ERRCODE = '28000';
  END IF;

  -- Expire both halves of an old request atomically.
  WITH expired_access AS (
    UPDATE public.permanent_qr_access_requests
    SET status = 'expired', updated_at = now()
    WHERE restaurant_table_id = v_table.id
      AND status = 'pending'
      AND expires_at <= now()
    RETURNING service_request_id
  )
  UPDATE public.service_requests sr
  SET status = 'expired'
  FROM expired_access ea
  WHERE sr.id = ea.service_request_id AND sr.status = 'pending';

  SELECT * INTO v_request
  FROM public.permanent_qr_access_requests
  WHERE restaurant_table_id = v_table.id
    AND status = 'pending'
    AND expires_at > now()
  ORDER BY requested_at DESC LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('request_id', v_request.id, 'status', 'pending',
      'expires_at', v_request.expires_at, 'table_number', v_table.table_number);
  END IF;

  v_service_id := gen_random_uuid();
  INSERT INTO public.service_requests
    (id, merchant_id, branch_id, restaurant_table_id, dining_area_id,
     table_number, request_type, status, created_at, expires_at)
  VALUES
    (v_service_id, v_table.merchant_id, v_table.branch_id, v_table.id,
     v_table.dining_area_id, v_table.table_number,
     'Permanent QR - confirm table', 'pending', now(), now() + interval '5 minutes');

  INSERT INTO public.permanent_qr_access_requests
    (merchant_id, branch_id, restaurant_table_id, table_number,
     service_request_id, expires_at)
  VALUES
    (v_table.merchant_id, v_table.branch_id, v_table.id, v_table.table_number,
     v_service_id, now() + interval '5 minutes')
  RETURNING * INTO v_request;

  RETURN jsonb_build_object('request_id', v_request.id, 'status', 'pending',
    'expires_at', v_request.expires_at, 'table_number', v_table.table_number);
END;
$$;

REVOKE ALL ON FUNCTION public.request_permanent_qr_access(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_permanent_qr_access(uuid,text,text) TO service_role;

NOTIFY pgrst, 'reload schema';
