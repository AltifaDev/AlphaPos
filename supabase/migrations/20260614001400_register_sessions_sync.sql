-- =========================================================================
-- Migration 012: Register Sessions Cloud Synchronization
-- Created: 2026-06-14
-- Description: Creates the register_sessions table for cash drawer sessions
--              enabling central cloud auditing of cash discrepancy.
-- =========================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.register_sessions (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    opened_by_user_id UUID NOT NULL,
    closed_by_user_id UUID,
    opened_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,
    opening_cash DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    expected_closing_cash DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    actual_closing_cash DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    cash_discrepancy DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    notes TEXT,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE public.register_sessions ENABLE ROW LEVEL SECURITY;

-- Create Isolation Policy
DROP POLICY IF EXISTS "merchant_isolation_register_sessions" ON public.register_sessions;
CREATE POLICY "merchant_isolation_register_sessions" ON public.register_sessions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- Indexes for querying cash audits
CREATE INDEX IF NOT EXISTS idx_register_sessions_merchant ON public.register_sessions (merchant_id);
CREATE INDEX IF NOT EXISTS idx_register_sessions_branch ON public.register_sessions (branch_id);
CREATE INDEX IF NOT EXISTS idx_register_sessions_opened_at ON public.register_sessions (merchant_id, opened_at DESC);

COMMIT;
