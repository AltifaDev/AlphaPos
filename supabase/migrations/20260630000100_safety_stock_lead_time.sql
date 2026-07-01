-- ============================================================
-- Migration: Safety Stock, Max Stock Level & Lead Time
-- AlphaPos — Inventory Best Practice (ISO 9001 / GS1)
-- ============================================================
-- Adds 3 columns to inventory_items:
--   safety_stock_level  — buffer stock qty (default 0 = not configured)
--   max_stock_level     — ceiling for over-order alert (0 = unlimited)
--   lead_time_days      — supplier delivery days for ROP calculation
-- Adds server-side reorder_point computed column + alerting view.
-- ============================================================

-- ── 1. New columns on inventory_items ───────────────────────────────────────
ALTER TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS safety_stock_level  NUMERIC(12,4) NOT NULL DEFAULT 0.0000,
    ADD COLUMN IF NOT EXISTS max_stock_level     NUMERIC(12,4) NOT NULL DEFAULT 0.0000,
    ADD COLUMN IF NOT EXISTS lead_time_days      INTEGER       NOT NULL DEFAULT 1
        CHECK (lead_time_days >= 0);

-- ── 2. Reorder-Point helper function ────────────────────────────────────────
-- reorder_point(item_id)
--   = safety_stock_level + (avg_daily_usage_30d × lead_time_days)
-- avg_daily_usage_30d is approximated from inventory_transactions.
CREATE OR REPLACE FUNCTION public.item_reorder_point(p_item_id UUID)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    WITH usage_30d AS (
        SELECT COALESCE(SUM(quantity), 0) AS total_used
        FROM public.inventory_transactions
        WHERE inventory_item_id = p_item_id
          AND transaction_type IN ('sell', 'waste')
          AND is_deleted = FALSE
          AND updated_at >= NOW() - INTERVAL '30 days'
    )
    SELECT
        i.safety_stock_level
        + (u.total_used / 30.0 * i.lead_time_days)
    FROM public.inventory_items i, usage_30d u
    WHERE i.id = p_item_id;
$$;

-- ── 3. Reorder Alerts View ───────────────────────────────────────────────────
-- Fast server-side view for dashboard queries.
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

-- ── 4. Grant select on view to authenticated role ────────────────────────────
GRANT SELECT ON public.reorder_alerts TO authenticated;

-- ── 5. Index to speed up low-stock queries ───────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_inventory_items_stock_levels
    ON public.inventory_items (merchant_id, current_quantity, reorder_level)
    WHERE is_deleted = FALSE;

-- ── Done. ────────────────────────────────────────────────────────────────────
