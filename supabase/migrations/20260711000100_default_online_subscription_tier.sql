-- =========================================================================
-- Migration: Default Legacy Merchants to Online Cloud Subscription
-- Date: 2026-07-11
-- Description:
--   Older merchants may have NULL/blank subscription_tier values. Treat those
--   merchants as online cloud stores so device sync does not silently fall back
--   to offline mode.
-- =========================================================================

ALTER TABLE public.merchants
    ALTER COLUMN subscription_tier SET DEFAULT 'online_subscription';

UPDATE public.merchants
SET subscription_tier = 'online_subscription',
    subscription_status = COALESCE(NULLIF(subscription_status, ''), 'active')
WHERE subscription_tier IS NULL
   OR btrim(subscription_tier) = '';
