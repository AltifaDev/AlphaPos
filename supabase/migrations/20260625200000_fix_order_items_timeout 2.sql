-- ============================================================================
-- Migration: fix order_items INSERT timeout
-- Root cause: POST order_items times out (>5s) because:
--   1. No index on order_items(merchant_id) → RLS full seq scan per row
--   2. No index on order_items(order_id)    → PostgREST join full seq scan
--
-- This migration is IDEMPOTENT — safe to run multiple times.
-- Run this on Supabase production if "Sync Failed" still shows on iPad.
-- ============================================================================

BEGIN;

-- ── 1. Ensure indexes exist (idempotent) ─────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON public.order_items (order_id);

CREATE INDEX IF NOT EXISTS idx_order_items_merchant_id
    ON public.order_items (merchant_id);

CREATE INDEX IF NOT EXISTS idx_order_items_merchant_order
    ON public.order_items (merchant_id, order_id);

CREATE INDEX IF NOT EXISTS idx_order_items_merchant_status
    ON public.order_items (merchant_id, status)
    WHERE status NOT IN ('cancelled', 'served');

-- ── 2. Ensure orders indexes exist ───────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_orders_merchant_status
    ON public.orders (merchant_id, status)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_orders_merchant_created
    ON public.orders (merchant_id, created_at DESC)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_orders_table_number
    ON public.orders (table_number, merchant_id)
    WHERE status NOT IN ('cancelled', 'completed');

-- ── 3. Ensure RLS + GRANT are correct for order_items ───────────────────

-- Re-enable RLS (idempotent)
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- Drop and recreate tenant_isolation policy to ensure correct definition
DROP POLICY IF EXISTS tenant_isolation ON public.order_items;
CREATE POLICY tenant_isolation
    ON public.order_items
    FOR ALL TO public
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

-- Ensure anon + authenticated have full DML access
-- (tenant_isolation policy restricts to own merchant data via RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_items TO anon, authenticated;

-- ── 4. Ensure RLS + GRANT are correct for orders ─────────────────────────

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation ON public.orders;
CREATE POLICY tenant_isolation
    ON public.orders
    FOR ALL TO public
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders TO anon, authenticated;

-- ── 5. Verify get_active_merchant_id() function exists ───────────────────

-- The function reads merchant_id from:
--   1. JWT claim: request.jwt.claims ->> 'merchant_id'
--   2. Custom header: request.headers ->> 'x-merchant-id'
-- iPad sends x-merchant-id header on every request (NetworkManager.swift).

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'get_active_merchant_id'
          AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'CRITICAL: get_active_merchant_id() function not found! RLS will block all requests.';
    END IF;
END;
$$;

COMMIT;
