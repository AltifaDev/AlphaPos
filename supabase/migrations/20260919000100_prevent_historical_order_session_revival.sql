-- Prevent historical dine-in orders from being attached to a newly opened
-- table session. Table numbers are reusable; table_session_id + time window
-- are the operational identity of a bill.

CREATE OR REPLACE FUNCTION public.enforce_order_session_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_session public.table_sessions;
  v_order_created_at timestamptz;
  v_session_started_at timestamptz;
BEGIN
  IF NEW.table_session_id IS NOT NULL THEN
    SELECT * INTO v_session FROM public.table_sessions WHERE id = NEW.table_session_id;
  ELSIF NULLIF(NEW.session_token, '') IS NOT NULL THEN
    SELECT * INTO v_session FROM public.table_sessions WHERE session_token = NEW.session_token;
  END IF;

  IF v_session.id IS NULL THEN
    IF NEW.order_source = 'web' AND COALESCE(NEW.order_type, 'dine_in') = 'dine_in' THEN
      RAISE EXCEPTION 'web_dine_in_order_requires_active_table_session'
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF v_session.is_active <> 1 OR v_session.ended_at IS NOT NULL THEN
    RAISE EXCEPTION 'order_table_session_is_closed' USING ERRCODE = '23514';
  END IF;
  IF NEW.merchant_id IS DISTINCT FROM v_session.merchant_id
     OR NEW.branch_id IS DISTINCT FROM v_session.branch_id
     OR NEW.table_number IS DISTINCT FROM v_session.table_number THEN
    RAISE EXCEPTION 'order_table_session_scope_mismatch' USING ERRCODE = '23514';
  END IF;

  v_order_created_at := COALESCE(NEW.created_at, now());
  v_session_started_at := COALESCE(v_session.started_at, v_session.created_at);
  IF v_session_started_at IS NULL
     OR v_order_created_at < v_session_started_at - interval '5 minutes'
     OR v_order_created_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'order_table_session_time_mismatch' USING ERRCODE = '23514';
  END IF;

  NEW.table_session_id := v_session.id;
  NEW.session_token := v_session.session_token;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_enforce_session_scope ON public.orders;
CREATE TRIGGER trg_orders_enforce_session_scope
  BEFORE INSERT OR UPDATE OF table_session_id, session_token, merchant_id,
    branch_id, table_number, created_at
  ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.enforce_order_session_scope();

-- Quarantine legacy invalid links without deleting sales history. These rows
-- remain reportable but can no longer enter a live table cart through a reused
-- table number.
UPDATE public.orders AS o
SET table_session_id = NULL,
    session_token = NULL,
    updated_at = now()
FROM public.table_sessions AS s
WHERE o.table_session_id = s.id
  AND COALESCE(o.order_type, 'dine_in') = 'dine_in'
  AND (
    COALESCE(s.started_at, s.created_at) IS NULL
    OR o.created_at < COALESCE(s.started_at, s.created_at) - interval '5 minutes'
  );

CREATE INDEX IF NOT EXISTS idx_orders_live_session_created_at
  ON public.orders (table_session_id, created_at DESC)
  WHERE is_deleted = false AND table_session_id IS NOT NULL;

COMMENT ON FUNCTION public.enforce_order_session_scope() IS
'Rejects closed, cross-tenant, cross-table, future-dated, and historical order/session links.';
