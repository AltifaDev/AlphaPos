-- Durable Quick Service checkout/payment lifecycle.
-- Idempotent and safe to apply before the corresponding app release.

CREATE TABLE IF NOT EXISTS public.checkout_sessions (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    service_mode TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'open',
    version INTEGER NOT NULL DEFAULT 1,
    locked_by_device TEXT,
    locked_at TIMESTAMPTZ,
    parked_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT checkout_sessions_state_check CHECK
      (state IN ('open','parked','processing','completed','abandoned')),
    CONSTRAINT checkout_sessions_mode_check CHECK
      (service_mode IN ('table_service','quick_service','takeaway','delivery'))
);

CREATE TABLE IF NOT EXISTS public.payment_attempts (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    checkout_session_id UUID REFERENCES public.checkout_sessions(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    idempotency_key TEXT NOT NULL,
    method TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'THB',
    status TEXT NOT NULL DEFAULT 'created',
    provider_reference TEXT,
    failure_reason TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT payment_attempts_state_check CHECK
      (status IN ('created','awaiting_customer','processing','requires_action',
                  'authorized','captured','failed','cancelled','expired','unknown')),
    CONSTRAINT payment_attempts_idempotency_unique UNIQUE (merchant_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_checkout_sessions_merchant_state
    ON public.checkout_sessions (merchant_id, state, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_order
    ON public.checkout_sessions (order_id);
CREATE INDEX IF NOT EXISTS idx_payment_attempts_checkout
    ON public.payment_attempts (checkout_session_id, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_attempt_provider_reference
    ON public.payment_attempts (merchant_id, provider_reference)
    WHERE provider_reference IS NOT NULL AND is_deleted = false;

ALTER TABLE public.checkout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_isolation_checkout_sessions ON public.checkout_sessions;
CREATE POLICY merchant_isolation_checkout_sessions ON public.checkout_sessions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

DROP POLICY IF EXISTS merchant_isolation_payment_attempts ON public.payment_attempts;
CREATE POLICY merchant_isolation_payment_attempts ON public.payment_attempts
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- Payment rows may now represent provider lifecycle states. Existing rows stay completed.
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS provider_reference TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_merchant_idempotency
    ON public.payments (merchant_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
