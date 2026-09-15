-- =========================================================================
-- Migration: Inventory Transaction Event-Time Reporting
-- Created: 2026-07-11
-- Description:
--   Reports (waste, COGS, consumption, safety-stock usage) must be dated by
--   WHEN the stock movement happened, not when the row was last synced.
--
--   The client historically uploaded `created_at = now()` at sync time and had
--   no dedicated event timestamp in its local model, so re-syncing an old row
--   pushed it into the current reporting window. The Swift model now owns an
--   explicit `created_at` (event time) and uploads it verbatim.
--
--   This migration:
--     1. Guarantees the `created_at` column exists (it does in fresh schemas;
--        this is defensive for older provisioned databases).
--     2. Adds a reporting index on (merchant_id, created_at).
--     3. Adds a composite index for per-item time-ranged usage queries used by
--        the safety-stock / reorder-point calculator.
--     4. Documents the column semantics so future code keeps the contract.
-- =========================================================================

BEGIN;

-- 1. Defensive: ensure the event-time column exists on older databases.
ALTER TABLE public.inventory_transactions
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- 2. Reporting index: merchant-scoped, time-ranged scans (daily/tax/inventory).
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_merchant_created
    ON public.inventory_transactions (merchant_id, created_at);

-- 3. Per-item, type-filtered usage window (safety stock / reorder point).
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item_type_created
    ON public.inventory_transactions (item_id, transaction_type, created_at);

-- 4. Document the semantics of the timestamp columns.
COMMENT ON COLUMN public.inventory_transactions.created_at IS
    'Business event time — when the stock movement actually occurred. Authoritative for all reporting. Set by the client, never overwritten on re-sync.';
COMMENT ON COLUMN public.inventory_transactions.updated_at IS
    'Sync metadata — last time the row was written/uploaded. Do NOT use for reporting or dating a movement.';

COMMIT;
