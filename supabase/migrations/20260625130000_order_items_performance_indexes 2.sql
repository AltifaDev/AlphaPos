-- ============================================================================
-- Migration: order_items performance indexes
-- Problem: order_items table has NO index on order_id (FK column), causing
--          full sequential scans on every joined query select(*,order_items(*)).
--          This is the root cause of the "items not loading" bug:
--            - join takes 2-10s on large tables → exceeds 5s timeout → throw
--            - both AlphaPos (iPad) and AlphaPosStaff (iPhone) affected
-- ============================================================================

BEGIN;

-- ─── 1. Core lookup indexes (these are the critical ones) ─────────────────

-- Fastest path for PostgREST join: orders LEFT JOIN order_items ON order_id
-- Without this, every joined query does a full seq scan of order_items.
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON public.order_items (order_id);

-- RLS policy evaluates merchant_id on every row — needs an index.
-- Also used in direct fetchOrderItems calls.
CREATE INDEX IF NOT EXISTS idx_order_items_merchant_id
    ON public.order_items (merchant_id);

-- ─── 2. Composite index for the most common query pattern ─────────────────
-- fetchTableOrders: WHERE merchant_id = $1 JOIN order_items ON order_id
-- This composite covers RLS check + join in one index scan.
CREATE INDEX IF NOT EXISTS idx_order_items_merchant_order
    ON public.order_items (merchant_id, order_id);

-- ─── 3. Status index for active-items-only queries ─────────────────────────
-- AlphaPosStaff filters: status != 'cancelled' && status != 'served'
CREATE INDEX IF NOT EXISTS idx_order_items_merchant_status
    ON public.order_items (merchant_id, status)
    WHERE status NOT IN ('cancelled', 'served');

-- ─── 4. item_id index for menu item resolution ────────────────────────────
-- SyncEngine re-resolves menuItem by item_id — currently no index on TEXT column.
CREATE INDEX IF NOT EXISTS idx_order_items_item_id
    ON public.order_items (item_id)
    WHERE item_id IS NOT NULL;

-- ─── 5. orders table: missing index on merchant_id + status ───────────────
-- fetchCustomerOrders: WHERE merchant_id=$1 AND status IN (...)
-- Current schema only has idx_orders_table_session — no merchant+status index.
CREATE INDEX IF NOT EXISTS idx_orders_merchant_status
    ON public.orders (merchant_id, status)
    WHERE is_deleted = false;

-- ─── 6. orders table: merchant_id + created_at for time-sorted queries ───
CREATE INDEX IF NOT EXISTS idx_orders_merchant_created
    ON public.orders (merchant_id, created_at DESC)
    WHERE is_deleted = false;

COMMIT;
