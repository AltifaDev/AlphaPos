-- =========================================================================
-- Migration 036: Add Merchant Subscription Fields
-- Date: 2026-06-30
-- Description:
--   Adds billing/subscription fields to public.merchants to support monthly,
--   annual, and perpetual packages.
-- =========================================================================

ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS subscription_tier VARCHAR(100) DEFAULT 'offline_perpetual';
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS subscription_status VARCHAR(50) DEFAULT 'active';
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMP WITH TIME ZONE;
