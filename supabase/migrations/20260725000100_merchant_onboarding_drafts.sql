-- Phase 5: server-side onboarding drafts so merchants can resume shop/plan setup.

CREATE TABLE IF NOT EXISTS public.merchant_onboarding_drafts (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    shop_name text,
    shop_phone text,
    currency text DEFAULT 'THB',
    tax_id text,
    subscription_tier text,
    billing_cycle text,
    first_name text,
    last_name text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_merchant_onboarding_drafts_updated
    ON public.merchant_onboarding_drafts (updated_at DESC);

ALTER TABLE public.merchant_onboarding_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_onboarding_drafts_own ON public.merchant_onboarding_drafts;
CREATE POLICY merchant_onboarding_drafts_own
    ON public.merchant_onboarding_drafts
    FOR ALL
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.merchant_onboarding_drafts TO authenticated;
GRANT ALL ON public.merchant_onboarding_drafts TO service_role;

COMMENT ON TABLE public.merchant_onboarding_drafts IS
    'Incomplete merchant signup shop/plan fields; cleared after activate-merchant succeeds.';
