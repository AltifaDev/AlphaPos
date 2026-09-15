BEGIN;

-- Idempotent repair for installations where the accounting-aware client was
-- deployed before the complete business-date schema migration reached the DB.
ALTER TABLE public.branches
  ADD COLUMN IF NOT EXISTS business_day_cutoff_hour SMALLINT NOT NULL DEFAULT 4,
  ADD COLUMN IF NOT EXISTS time_zone_id TEXT NOT NULL DEFAULT 'Asia/Bangkok';

ALTER TABLE public.register_sessions ADD COLUMN IF NOT EXISTS business_date DATE;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS business_date DATE,
  ADD COLUMN IF NOT EXISTS register_session_id UUID REFERENCES public.register_sessions(id) ON DELETE SET NULL;
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS business_date DATE,
  ADD COLUMN IF NOT EXISTS register_session_id UUID REFERENCES public.register_sessions(id) ON DELETE SET NULL;
ALTER TABLE public.refund_transactions
  ADD COLUMN IF NOT EXISTS business_date DATE,
  ADD COLUMN IF NOT EXISTS register_session_id UUID REFERENCES public.register_sessions(id) ON DELETE SET NULL;
ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS business_date DATE,
  ADD COLUMN IF NOT EXISTS register_session_id UUID REFERENCES public.register_sessions(id) ON DELETE SET NULL;

UPDATE public.register_sessions AS session
SET business_date = (
  session.opened_at AT TIME ZONE COALESCE(branch.time_zone_id, 'Asia/Bangkok')
  - make_interval(hours => COALESCE(branch.business_day_cutoff_hour, 4))
)::DATE
FROM public.branches AS branch
WHERE branch.id = session.branch_id AND session.business_date IS NULL;

UPDATE public.orders AS order_row
SET business_date = (
  order_row.created_at AT TIME ZONE COALESCE(branch.time_zone_id, 'Asia/Bangkok')
  - make_interval(hours => COALESCE(branch.business_day_cutoff_hour, 4))
)::DATE
FROM public.branches AS branch
WHERE branch.id = order_row.branch_id AND order_row.business_date IS NULL;

UPDATE public.payments AS payment
SET business_date = (
  payment.created_at AT TIME ZONE COALESCE(branch.time_zone_id, 'Asia/Bangkok')
  - make_interval(hours => COALESCE(branch.business_day_cutoff_hour, 4))
)::DATE
FROM public.orders AS order_row
JOIN public.branches AS branch ON branch.id = order_row.branch_id
WHERE payment.order_id = order_row.id AND payment.business_date IS NULL;

UPDATE public.payments AS payment
SET register_session_id = (
  SELECT session.id
  FROM public.register_sessions AS session
  JOIN public.orders AS order_row ON order_row.branch_id = session.branch_id
  WHERE order_row.id = payment.order_id
    AND session.opened_at <= payment.created_at
    AND (session.closed_at IS NULL OR session.closed_at >= payment.created_at)
  ORDER BY session.opened_at DESC
  LIMIT 1
)
WHERE payment.register_session_id IS NULL;

UPDATE public.orders AS order_row
SET register_session_id = (
      SELECT payment.register_session_id
      FROM public.payments AS payment
      WHERE payment.order_id = order_row.id
      ORDER BY payment.created_at
      LIMIT 1
    ),
    business_date = COALESCE((
      SELECT payment.business_date
      FROM public.payments AS payment
      WHERE payment.order_id = order_row.id
      ORDER BY payment.created_at
      LIMIT 1
    ), order_row.business_date)
WHERE EXISTS (
  SELECT 1 FROM public.payments AS payment WHERE payment.order_id = order_row.id
);

UPDATE public.refund_transactions AS refund
SET business_date = (
  refund.created_at AT TIME ZONE COALESCE(branch.time_zone_id, 'Asia/Bangkok')
  - make_interval(hours => COALESCE(branch.business_day_cutoff_hour, 4))
)::DATE
FROM public.orders AS order_row
JOIN public.branches AS branch ON branch.id = order_row.branch_id
WHERE refund.order_id = order_row.id AND refund.business_date IS NULL;

UPDATE public.inventory_transactions AS transaction_row
SET business_date = (
  transaction_row.created_at AT TIME ZONE COALESCE(branch.time_zone_id, 'Asia/Bangkok')
  - make_interval(hours => COALESCE(branch.business_day_cutoff_hour, 4))
)::DATE
FROM public.branches AS branch
WHERE branch.id = transaction_row.branch_id AND transaction_row.business_date IS NULL;

CREATE INDEX IF NOT EXISTS idx_orders_branch_business_date
  ON public.orders(branch_id, business_date);
CREATE INDEX IF NOT EXISTS idx_payments_merchant_business_date
  ON public.payments(merchant_id, business_date);
CREATE INDEX IF NOT EXISTS idx_inventory_txn_branch_business_date
  ON public.inventory_transactions(branch_id, business_date);
CREATE INDEX IF NOT EXISTS idx_payments_register_session
  ON public.payments(register_session_id);
CREATE INDEX IF NOT EXISTS idx_inventory_txn_register_session
  ON public.inventory_transactions(register_session_id);

-- Force PostgREST to see the repaired columns immediately after commit.
NOTIFY pgrst, 'reload schema';

COMMIT;
