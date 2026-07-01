-- ============================================================
-- Migration: Secure Device Pairing Tokens Table
-- Date: 2026-07-01
-- ============================================================

CREATE TABLE IF NOT EXISTS public.device_pairing_tokens (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id   UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    branch_id     UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    token         VARCHAR(128) UNIQUE NOT NULL,
    pairing_code  VARCHAR(6) NOT NULL,
    expires_at    TIMESTAMP WITH TIME ZONE NOT NULL,
    is_used       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE public.device_pairing_tokens ENABLE ROW LEVEL SECURITY;

-- Drop policy if exists
DROP POLICY IF EXISTS "pairing_tokens_access_policy" ON public.device_pairing_tokens;

-- Policy: Allow anonymous/authenticated read & write to handle client-side registration exchange
CREATE POLICY "pairing_tokens_access_policy" ON public.device_pairing_tokens
    FOR ALL TO anon, authenticated
    USING (TRUE)
    WITH CHECK (TRUE);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_device_pairing_tokens_code ON public.device_pairing_tokens (pairing_code);
CREATE INDEX IF NOT EXISTS idx_device_pairing_tokens_token ON public.device_pairing_tokens (token);

GRANT ALL ON public.device_pairing_tokens TO anon, authenticated, service_role;
