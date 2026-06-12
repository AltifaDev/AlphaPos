-- ==============================================================================
-- Migration 007: Add PromptPay number to merchants table
-- Date: 2026-06-12
-- Purpose: Add promptpay_number column to merchants table for dynamic QR Code generation
-- ==============================================================================

-- ✅ Part A: Add promptpay_number column to merchants
ALTER TABLE IF EXISTS public.merchants 
ADD COLUMN IF NOT EXISTS promptpay_number VARCHAR(50);

-- ✅ Part B: Update RLS Policies if necessary (public.merchants table already has policies)
-- The merchants table has:
-- CREATE POLICY "merchant_isolation_merchants" ON merchants FOR SELECT TO public USING (id = get_active_merchant_id());
-- The new column will automatically be protected by these policies.
