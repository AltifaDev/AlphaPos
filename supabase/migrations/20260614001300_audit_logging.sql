-- =========================================================================
-- Migration 011: Audit Logging System (Anti-Fraud Trail)
-- Created: 2026-06-14
-- Description: Creates the audit_logs table for keeping a security log of
--              sensitive actions (Voids, Refunds, Pricing edits, etc.)
-- =========================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    action_type VARCHAR(100) NOT NULL, -- e.g., 'item_void', 'refund', 'price_override', 'discount_applied'
    details TEXT,
    original_value DECIMAL(10,2),
    new_value DECIMAL(10,2),
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Enable RLS
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Create Isolation Policy
DROP POLICY IF EXISTS "merchant_isolation_audit_logs" ON public.audit_logs;
CREATE POLICY "merchant_isolation_audit_logs" ON public.audit_logs
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- Indexes for querying audit history efficiently
CREATE INDEX IF NOT EXISTS idx_audit_logs_merchant ON public.audit_logs (merchant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs (merchant_id, action_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs (merchant_id, created_at DESC);

COMMIT;
