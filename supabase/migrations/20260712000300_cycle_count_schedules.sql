-- ============================================================
-- Migration: Cycle Count Schedules (ABC-based stocktaking)
-- AlphaPos — Inventory Best Practice (ISO 9001 cycle counting)
-- ============================================================
-- Replaces annual wall-to-wall stocktakes with risk-based cycle counting:
--   A items → counted weekly, B → monthly, C → quarterly.
-- The client (CycleCountManager) generates/updates these rows from the ABC
-- classification of annual usage value.

CREATE TABLE IF NOT EXISTS public.cycle_count_schedules (
    id                UUID PRIMARY KEY,
    merchant_id       UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    inventory_item_id UUID REFERENCES public.inventory_items(id) ON DELETE SET NULL,
    branch_id         UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    abc_class         TEXT NOT NULL CHECK (abc_class IN ('A','B','C')),
    frequency_days    INTEGER NOT NULL DEFAULT 30 CHECK (frequency_days > 0),
    last_count_date   TIMESTAMPTZ,
    next_due_date     TIMESTAMPTZ NOT NULL,
    is_deleted        BOOLEAN NOT NULL DEFAULT FALSE,
    is_synced         BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cycle_count_schedules_due
    ON public.cycle_count_schedules (merchant_id, next_due_date)
    WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_cycle_count_schedules_item
    ON public.cycle_count_schedules (inventory_item_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.cycle_count_schedules TO authenticated;
