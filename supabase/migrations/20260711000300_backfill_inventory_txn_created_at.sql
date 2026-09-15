-- =========================================================================
-- Migration: Backfill inventory_transactions.created_at (event time)
-- Created: 2026-07-11
-- Depends on: 20260711000200_inventory_txn_event_time.sql
-- Description:
--   Historically the client uploaded `created_at = now()` at SYNC time rather
--   than the real movement time, so rows already in Supabase may be mis-dated
--   (all bunched around their sync moment). This one-shot backfill repairs
--   historical rows using the best available event time:
--
--     1. If the transaction references an order line (reference_id → orders.id),
--        use that order's created_at — the true business event time.
--     2. Otherwise fall back to the row's own updated_at, which is much closer
--        to the real event time than the sync timestamp.
--
--   The update is conservative: it only rewrites rows where created_at is
--   clearly later than the fallback (the mis-dating signature), so correctly
--   dated rows and future re-runs are no-ops (idempotent).
--
--   NOTE: reference_id on a "sell" transaction maps to an OrderItem id in the
--   Swift model, but historically some rows stored the Order id. We therefore
--   join defensively against BOTH orders.id and order_items.id.
-- =========================================================================

BEGIN;

-- 1. Repair using the referenced order's created_at (via order_items → orders).
WITH ref_event_time AS (
    SELECT it.id AS txn_id,
           COALESCE(o_direct.created_at, o_via_item.created_at) AS event_time
    FROM public.inventory_transactions it
    LEFT JOIN public.orders o_direct
           ON o_direct.id = it.reference_id
    LEFT JOIN public.order_items oi
           ON oi.id = it.reference_id
    LEFT JOIN public.orders o_via_item
           ON o_via_item.id = oi.order_id
    WHERE it.reference_id IS NOT NULL
)
UPDATE public.inventory_transactions it
SET created_at = ref.event_time
FROM ref_event_time ref
WHERE it.id = ref.txn_id
  AND ref.event_time IS NOT NULL
  AND it.created_at > ref.event_time + INTERVAL '5 seconds';

-- 2. Fallback: rows with no usable order reference — pull back to updated_at
--    when created_at is later than updated_at (the mis-dating signature).
UPDATE public.inventory_transactions
SET created_at = updated_at
WHERE updated_at IS NOT NULL
  AND created_at > updated_at + INTERVAL '5 seconds';

COMMIT;
