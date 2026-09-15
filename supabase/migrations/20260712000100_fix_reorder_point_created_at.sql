-- ============================================================
-- Migration: Reorder Point — use business event time (created_at)
-- AlphaPos — Inventory Best Practice (ISO 9001 / GS1)
-- ============================================================
-- The previous version of item_reorder_point() measured 30-day usage from
-- `updated_at`. Per migration 20260711000200_inventory_txn_event_time.sql the
-- authoritative business timestamp for a movement is `created_at` (updated_at
-- changes on every re-sync and would otherwise double-count movements).
-- This re-creates the function using `created_at` so the reorder point and the
-- reorder_alerts view are computed correctly.
-- ============================================================

CREATE OR REPLACE FUNCTION public.item_reorder_point(p_item_id UUID)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    WITH usage_30d AS (
        SELECT COALESCE(SUM(quantity), 0) AS total_used
        FROM public.inventory_transactions
        WHERE item_id = p_item_id
          AND transaction_type IN ('sell', 'waste')
          AND is_deleted = FALSE
          AND created_at >= NOW() - INTERVAL '30 days'
    )
    SELECT
        i.safety_stock_level
        + (u.total_used / 30.0 * i.lead_time_days)
    FROM public.inventory_items i, usage_30d u
    WHERE i.id = p_item_id;
$$;

-- Refresh the dependent view (recreate to pick up the new function body).
DROP VIEW IF EXISTS public.reorder_alerts;
CREATE OR REPLACE VIEW public.reorder_alerts AS
SELECT
    i.id                                    AS item_id,
    i.merchant_id,
    i.name                                  AS item_name,
    i.unit,
    i.current_quantity,
    i.reorder_level,
    i.safety_stock_level,
    i.max_stock_level,
    i.lead_time_days,
    public.item_reorder_point(i.id)        AS reorder_point,
    s.name                                  AS supplier_name,
    b.name                                  AS branch_name,
    CASE
        WHEN i.current_quantity <= 0
            THEN 'out_of_stock'
        WHEN i.current_quantity <= public.item_reorder_point(i.id)
            THEN 'at_reorder_point'
        WHEN i.safety_stock_level > 0
             AND i.current_quantity <= i.safety_stock_level
            THEN 'below_safety'
        WHEN i.current_quantity <= i.reorder_level
            THEN 'low_stock'
        WHEN i.max_stock_level > 0
             AND i.current_quantity > i.max_stock_level
            THEN 'overstock'
        ELSE 'adequate'
    END                                     AS stock_status,
    GREATEST(
        COALESCE(i.max_stock_level, i.reorder_level * 2),
        i.reorder_level * 2
    ) - i.current_quantity                  AS suggested_order_qty
FROM public.inventory_items    i
LEFT JOIN public.suppliers     s ON i.supplier_id = s.id
LEFT JOIN public.branches      b ON i.branch_id   = b.id
WHERE i.is_deleted = FALSE;

GRANT SELECT ON public.reorder_alerts TO authenticated;
