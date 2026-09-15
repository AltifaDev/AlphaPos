BEGIN;

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

UPDATE public.register_sessions s
SET business_date = (s.opened_at AT TIME ZONE COALESCE(b.time_zone_id,'Asia/Bangkok') - make_interval(hours => COALESCE(b.business_day_cutoff_hour,4)))::date
FROM public.branches b WHERE b.id=s.branch_id AND s.business_date IS NULL;

UPDATE public.payments p SET
  business_date=(p.created_at AT TIME ZONE COALESCE(b.time_zone_id,'Asia/Bangkok') - make_interval(hours => COALESCE(b.business_day_cutoff_hour,4)))::date
FROM public.orders o JOIN public.branches b ON b.id=o.branch_id
WHERE p.order_id=o.id AND p.business_date IS NULL;

UPDATE public.payments p SET register_session_id=(
  SELECT rs.id FROM public.register_sessions rs JOIN public.orders o ON o.branch_id=rs.branch_id
  WHERE o.id=p.order_id AND rs.opened_at<=p.created_at
    AND (rs.closed_at IS NULL OR rs.closed_at>=p.created_at)
  ORDER BY rs.opened_at DESC LIMIT 1
) WHERE p.register_session_id IS NULL;

UPDATE public.orders o SET
  business_date=(o.created_at AT TIME ZONE COALESCE(b.time_zone_id,'Asia/Bangkok') - make_interval(hours => COALESCE(b.business_day_cutoff_hour,4)))::date
FROM public.branches b WHERE b.id=o.branch_id AND o.business_date IS NULL;

UPDATE public.orders o SET
  register_session_id=(SELECT p.register_session_id FROM public.payments p WHERE p.order_id=o.id ORDER BY p.created_at LIMIT 1),
  business_date=COALESCE((SELECT p.business_date FROM public.payments p WHERE p.order_id=o.id ORDER BY p.created_at LIMIT 1),o.business_date)
WHERE EXISTS (SELECT 1 FROM public.payments p WHERE p.order_id=o.id);

UPDATE public.refund_transactions r SET
  business_date=(r.created_at AT TIME ZONE COALESCE(b.time_zone_id,'Asia/Bangkok') - make_interval(hours => COALESCE(b.business_day_cutoff_hour,4)))::date
FROM public.orders o JOIN public.branches b ON b.id=o.branch_id
WHERE r.order_id=o.id AND r.business_date IS NULL;

UPDATE public.inventory_transactions t SET
  business_date=(t.created_at AT TIME ZONE COALESCE(b.time_zone_id,'Asia/Bangkok') - make_interval(hours => COALESCE(b.business_day_cutoff_hour,4)))::date
FROM public.branches b WHERE b.id=t.branch_id AND t.business_date IS NULL;

CREATE INDEX IF NOT EXISTS idx_payments_merchant_business_date ON public.payments(merchant_id,business_date);
CREATE INDEX IF NOT EXISTS idx_orders_branch_business_date ON public.orders(branch_id,business_date);
CREATE INDEX IF NOT EXISTS idx_inventory_txn_branch_business_date ON public.inventory_transactions(branch_id,business_date);
CREATE INDEX IF NOT EXISTS idx_payments_register_session ON public.payments(register_session_id);
CREATE INDEX IF NOT EXISTS idx_inventory_txn_register_session ON public.inventory_transactions(register_session_id);

COMMENT ON COLUMN public.payments.business_date IS 'Immutable local retail business date; distinct from actual created_at.';
COMMENT ON COLUMN public.payments.register_session_id IS 'Exact till shift responsible for the tender.';
COMMIT;
