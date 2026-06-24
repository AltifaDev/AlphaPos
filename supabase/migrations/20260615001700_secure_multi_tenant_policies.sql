-- =========================================================================
-- Migration 015: Secure Multi-Tenant Policies
-- Created: 2026-06-15
-- Description: Secures the orders and table_sessions tables by dropping
--              overly permissive / duplicate RLS policies that bypassed
--              merchant_id check. Enforces strict merchant isolation on all operations.
-- =========================================================================

BEGIN;

-- 15.1 Drop orders_merchant_access policy on orders
-- This policy had a bypass: "OR (is_deleted = false AND table_session_id IS NOT NULL)"
-- which allowed any anonymous user to view/write any active orders of any merchant.
-- The generic policy "merchant_isolation_orders" is already in place and securely
-- checks: USING (merchant_id = get_active_merchant_id())
DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders;

-- 15.2 Drop duplicate table_sessions_merchant_access policy on table_sessions
-- The generic policy "merchant_isolation_table_sessions" is already in place and
-- securely isolates sessions: USING (merchant_id = get_active_merchant_id())
DROP POLICY IF EXISTS "table_sessions_merchant_access" ON public.table_sessions;

COMMIT;
