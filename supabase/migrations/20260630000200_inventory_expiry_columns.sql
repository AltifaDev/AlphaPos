-- ============================================================
-- Migration: Expiry Alert Threshold Columns on inventory_items
-- AlphaPos — Companion to migration_005_expiry_fefo.sql
-- ============================================================
-- Adds per-item alert window overrides used by InventoryExpiryManager:
--   expiry_warning_days  — days before expiry to show Warning badge  (default 7)
--   expiry_critical_days — days before expiry to show Critical badge (default 3)
--
-- These mirror the iOS SwiftData model fields added in InventoryItem.swift.
-- Safe to run multiple times (IF NOT EXISTS / DEFAULT guards).
-- ============================================================

-- ── 1. Add columns to inventory_items ───────────────────────────────────────
ALTER TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS expiry_warning_days  INTEGER NOT NULL DEFAULT 7
        CHECK (expiry_warning_days  >= 0),
    ADD COLUMN IF NOT EXISTS expiry_critical_days INTEGER NOT NULL DEFAULT 3
        CHECK (expiry_critical_days >= 0 AND expiry_critical_days <= expiry_warning_days);

-- ── 2. Update expiry_alerts view to use per-item thresholds ─────────────────
-- (Replaces the version from migration_005 which used hardcoded constants)
CREATE OR REPLACE VIEW public.expiry_alerts AS
SELECT
    l.id             AS lot_id,
    l.merchant_id,
    l.branch_id,
    l.inventory_item_id,
    i.name           AS item_name,
    i.unit           AS item_unit,
    l.lot_number,
    l.expiry_date,
    l.remaining_quantity,
    l.lot_cost_price,
    b.name           AS branch_name,
    CURRENT_DATE - l.expiry_date::DATE          AS days_overdue,
    l.expiry_date::DATE - CURRENT_DATE          AS days_remaining,
    i.expiry_warning_days,
    i.expiry_critical_days,
    CASE
        WHEN l.expiry_date < CURRENT_DATE
            THEN 'expired'
        WHEN l.expiry_date <= CURRENT_DATE + i.expiry_critical_days
            THEN 'critical'
        WHEN l.expiry_date <= CURRENT_DATE + i.expiry_warning_days
            THEN 'warning'
        ELSE 'ok'
    END AS expiry_status
FROM public.inventory_lots l
JOIN public.inventory_items i ON l.inventory_item_id = i.id
LEFT JOIN public.branches   b ON l.branch_id          = b.id
WHERE l.is_deleted = FALSE
  AND l.remaining_quantity > 0
  AND l.expiry_date IS NOT NULL;

-- ── 3. Grant SELECT to authenticated role ────────────────────────────────────
GRANT SELECT ON public.expiry_alerts TO authenticated;

-- ── Done. ────────────────────────────────────────────────────────────────────
