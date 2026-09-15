BEGIN;

CREATE TABLE public.subscription_change_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    provider_order_id text UNIQUE,
    provider_payment_id text UNIQUE,
    subscription_tier text NOT NULL CHECK (subscription_tier IN ('offline_perpetual', 'offline_subscription', 'online_subscription')),
    billing_cycle text NOT NULL CHECK (billing_cycle IN ('monthly', 'annual', 'perpetual')),
    amount_thb numeric(10,2) NOT NULL CHECK (amount_thb > 0),
    status text NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'paid', 'cancelled')),
    created_at timestamptz NOT NULL DEFAULT now(),
    paid_at timestamptz
);

ALTER TABLE public.subscription_change_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscription_change_requests_read_own
ON public.subscription_change_requests FOR SELECT TO authenticated
USING (merchant_id = public.get_active_merchant_id());
REVOKE ALL ON public.subscription_change_requests FROM anon, authenticated;
GRANT SELECT ON public.subscription_change_requests TO authenticated;

COMMIT;
