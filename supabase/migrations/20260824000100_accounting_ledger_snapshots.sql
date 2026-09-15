BEGIN;

CREATE TABLE IF NOT EXISTS public.financial_events (
  id uuid PRIMARY KEY,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  source_event_key text NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('sale_capture','refund','payment_void','cash_in','cash_out','government_subsidy','tip','rounding_adjustment','reversal')),
  source_type text NOT NULL,
  source_id uuid NOT NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  register_session_id uuid REFERENCES public.register_sessions(id) ON DELETE SET NULL,
  business_date date NOT NULL,
  occurred_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  amount numeric(14,2) NOT NULL,
  payment_method text,
  status text NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  revision_of_event_id uuid REFERENCES public.financial_events(id) ON DELETE RESTRICT,
  source_device_id text,
  is_late_adjustment boolean NOT NULL DEFAULT false,
  is_deleted boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, source_event_key)
);

CREATE TABLE IF NOT EXISTS public.shift_closure_snapshots (
  id uuid PRIMARY KEY,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  register_session_id uuid NOT NULL REFERENCES public.register_sessions(id) ON DELETE RESTRICT,
  business_date date NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  opened_at timestamptz NOT NULL,
  closed_at timestamptz NOT NULL CHECK (closed_at >= opened_at),
  opening_cash numeric(14,2) NOT NULL,
  gross_sales numeric(14,2) NOT NULL,
  discounts numeric(14,2) NOT NULL,
  net_sales numeric(14,2) NOT NULL,
  refunds numeric(14,2) NOT NULL,
  tax numeric(14,2) NOT NULL,
  service_charge numeric(14,2) NOT NULL,
  cash_sales numeric(14,2) NOT NULL,
  card_sales numeric(14,2) NOT NULL,
  qr_sales numeric(14,2) NOT NULL,
  other_sales numeric(14,2) NOT NULL,
  cash_in numeric(14,2) NOT NULL DEFAULT 0,
  cash_out numeric(14,2) NOT NULL DEFAULT 0,
  expected_cash numeric(14,2) NOT NULL,
  actual_cash numeric(14,2) NOT NULL,
  discrepancy numeric(14,2) NOT NULL,
  transaction_count integer NOT NULL DEFAULT 0,
  late_adjustment_total numeric(14,2) NOT NULL DEFAULT 0,
  generated_at timestamptz NOT NULL DEFAULT now(),
  generated_by_user_id uuid,
  UNIQUE (merchant_id, register_session_id, version)
);

CREATE TABLE IF NOT EXISTS public.daily_sales_snapshots (
  id uuid PRIMARY KEY,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  business_date date NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  gross_sales numeric(14,2) NOT NULL,
  discounts numeric(14,2) NOT NULL,
  net_sales numeric(14,2) NOT NULL,
  refunds numeric(14,2) NOT NULL,
  tax numeric(14,2) NOT NULL,
  service_charge numeric(14,2) NOT NULL,
  cash_sales numeric(14,2) NOT NULL,
  card_sales numeric(14,2) NOT NULL,
  qr_sales numeric(14,2) NOT NULL,
  other_sales numeric(14,2) NOT NULL,
  order_count integer NOT NULL DEFAULT 0,
  payment_count integer NOT NULL DEFAULT 0,
  late_adjustment_total numeric(14,2) NOT NULL DEFAULT 0,
  calculated_through timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, branch_id, business_date, version)
);

CREATE INDEX IF NOT EXISTS idx_financial_events_shift ON public.financial_events (merchant_id, branch_id, register_session_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_financial_events_business_day ON public.financial_events (merchant_id, branch_id, business_date, occurred_at);
CREATE INDEX IF NOT EXISTS idx_financial_events_calendar ON public.financial_events (merchant_id, branch_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_financial_events_order ON public.financial_events (merchant_id, order_id);
CREATE INDEX IF NOT EXISTS idx_shift_snapshots_business_day ON public.shift_closure_snapshots (merchant_id, branch_id, business_date);
CREATE INDEX IF NOT EXISTS idx_daily_snapshots_lookup ON public.daily_sales_snapshots (merchant_id, branch_id, business_date, version DESC);

CREATE OR REPLACE FUNCTION public.reject_posted_financial_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'financial events cannot be deleted; create a reversal';
  END IF;
  IF OLD.status = 'posted' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'posted financial events are immutable; create a reversal or adjustment';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_financial_events_immutable ON public.financial_events;
CREATE TRIGGER trg_financial_events_immutable
BEFORE UPDATE OR DELETE ON public.financial_events FOR EACH ROW
EXECUTE FUNCTION public.reject_posted_financial_event_mutation();

CREATE OR REPLACE FUNCTION public.reject_shift_snapshot_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'shift closure snapshots cannot be deleted';
  END IF;
  IF NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'shift closure snapshots are immutable; create the next version';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_shift_snapshots_immutable ON public.shift_closure_snapshots;
CREATE TRIGGER trg_shift_snapshots_immutable
BEFORE UPDATE OR DELETE ON public.shift_closure_snapshots FOR EACH ROW
EXECUTE FUNCTION public.reject_shift_snapshot_mutation();

-- Do not reject overlapping sessions at branch scope. A branch can legitimately
-- operate multiple registers at the same time. Enforce overlap only after a
-- stable register/terminal identifier is stored on register_sessions.
DROP TRIGGER IF EXISTS trg_register_session_no_overlap ON public.register_sessions;
DROP FUNCTION IF EXISTS public.reject_overlapping_register_session();

ALTER TABLE public.financial_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shift_closure_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_sales_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_isolation_financial_events ON public.financial_events;
CREATE POLICY merchant_isolation_financial_events ON public.financial_events
FOR ALL USING (merchant_id = public.get_active_merchant_id())
WITH CHECK (merchant_id = public.get_active_merchant_id());
DROP POLICY IF EXISTS merchant_isolation_shift_closure_snapshots ON public.shift_closure_snapshots;
CREATE POLICY merchant_isolation_shift_closure_snapshots ON public.shift_closure_snapshots
FOR ALL USING (merchant_id = public.get_active_merchant_id())
WITH CHECK (merchant_id = public.get_active_merchant_id());
DROP POLICY IF EXISTS merchant_isolation_daily_sales_snapshots ON public.daily_sales_snapshots;
CREATE POLICY merchant_isolation_daily_sales_snapshots ON public.daily_sales_snapshots
FOR ALL USING (merchant_id = public.get_active_merchant_id())
WITH CHECK (merchant_id = public.get_active_merchant_id());

-- This deployment grants broad default table privileges to API roles. Narrow
-- the accounting tables explicitly and keep them non-deletable at the grant layer.
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER
ON public.financial_events, public.shift_closure_snapshots, public.daily_sales_snapshots
FROM anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.financial_events TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.shift_closure_snapshots TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.daily_sales_snapshots TO anon, authenticated, service_role;

COMMIT;
