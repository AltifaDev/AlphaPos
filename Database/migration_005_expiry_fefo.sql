-- ============================================================
-- Migration 005: Expiry Date & FEFO Lot Tracking
-- AlphaPos — Restaurant Inventory Best Practice
-- ============================================================
-- Run this after: migration_004_session_integrity.sql
-- Safe to run multiple times (IF NOT EXISTS guards everywhere)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. inventory_lots  (new table)
--    Tracks individual received batches per inventory_item.
--    Multiple lots per item, consumed FEFO by the app.
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory_lots (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id          UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    branch_id            UUID REFERENCES branches(id) ON DELETE SET NULL,
    inventory_item_id    UUID NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,

    -- Lot identity
    lot_number           VARCHAR(100),                   -- Supplier batch ref (optional)
    received_date        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expiry_date          DATE,                           -- NULL = no-expiry item

    -- Quantities
    initial_quantity     DECIMAL(12, 4) NOT NULL CHECK (initial_quantity > 0),
    remaining_quantity   DECIMAL(12, 4) NOT NULL DEFAULT 0 CHECK (remaining_quantity >= 0),

    -- Cost for COGS accuracy
    lot_cost_price       DECIMAL(12, 4) NOT NULL DEFAULT 0.00,

    -- Audit reference
    source_transaction_id UUID,                          -- InventoryTransaction that created this lot

    -- Soft-delete / sync
    is_deleted           BOOLEAN NOT NULL DEFAULT FALSE,
    is_synced            BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT remaining_le_initial CHECK (remaining_quantity <= initial_quantity)
);

-- Indexes for FEFO query performance
CREATE INDEX IF NOT EXISTS idx_inventory_lots_item_branch
    ON inventory_lots (inventory_item_id, branch_id)
    WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_inventory_lots_expiry
    ON inventory_lots (expiry_date ASC NULLS LAST)
    WHERE is_deleted = FALSE AND remaining_quantity > 0;

CREATE INDEX IF NOT EXISTS idx_inventory_lots_merchant
    ON inventory_lots (merchant_id, updated_at DESC)
    WHERE is_deleted = FALSE;

-- ────────────────────────────────────────────────────────────
-- 2. Add expiry_alert_days to inventory_items
--    Stores per-item override for warning window.
-- ────────────────────────────────────────────────────────────
ALTER TABLE inventory_items
    ADD COLUMN IF NOT EXISTS expiry_warning_days  INTEGER NOT NULL DEFAULT 7,
    ADD COLUMN IF NOT EXISTS expiry_critical_days INTEGER NOT NULL DEFAULT 3;

-- ────────────────────────────────────────────────────────────
-- 3. Row-Level Security (RLS) for inventory_lots
-- ────────────────────────────────────────────────────────────
ALTER TABLE inventory_lots ENABLE ROW LEVEL SECURITY;

-- Merchant isolation: users can only see their own merchant's lots
CREATE POLICY IF NOT EXISTS "inventory_lots_merchant_isolation"
    ON inventory_lots
    FOR ALL
    USING (
        merchant_id = (
            SELECT merchant_id
            FROM merchant_users
            WHERE id = auth.uid()
        )
    );

-- ────────────────────────────────────────────────────────────
-- 4. DB Function: fefo_consume(item_id, branch_id, qty)
--    Atomically deducts qty from lots in FEFO order.
--    Returns JSONB with consumed lot IDs and total COGS.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fefo_consume(
    p_item_id   UUID,
    p_branch_id UUID,
    p_quantity  DECIMAL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lot             RECORD;
    v_remaining       DECIMAL := p_quantity;
    v_take            DECIMAL;
    v_total_cogs      DECIMAL := 0;
    v_consumed        JSONB   := '[]'::JSONB;
BEGIN
    -- Lock and iterate lots in FEFO order
    -- (expiry_date ASC NULLS LAST, then received_date ASC)
    FOR v_lot IN
        SELECT id, remaining_quantity, lot_cost_price
        FROM inventory_lots
        WHERE inventory_item_id = p_item_id
          AND branch_id         = p_branch_id
          AND is_deleted        = FALSE
          AND remaining_quantity > 0
        ORDER BY expiry_date ASC NULLS LAST, received_date ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        EXIT WHEN v_remaining <= 0;

        v_take := LEAST(v_lot.remaining_quantity, v_remaining);

        UPDATE inventory_lots
        SET remaining_quantity = remaining_quantity - v_take,
            updated_at         = CURRENT_TIMESTAMP
        WHERE id = v_lot.id;

        v_total_cogs := v_total_cogs + (v_take * v_lot.lot_cost_price);
        v_consumed   := v_consumed || jsonb_build_object(
            'lot_id',         v_lot.id,
            'quantity_taken', v_take,
            'lot_cost_price', v_lot.lot_cost_price
        );

        v_remaining := v_remaining - v_take;
    END LOOP;

    RETURN jsonb_build_object(
        'consumed',     v_consumed,
        'unfulfilled',  GREATEST(v_remaining, 0),
        'total_cogs',   v_total_cogs
    );
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 5. DB View: expiry_alerts
--    Precomputed view for dashboard queries — no app-side filter loop.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW expiry_alerts AS
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
    CURRENT_DATE - l.expiry_date::DATE AS days_overdue,   -- positive = expired
    l.expiry_date::DATE - CURRENT_DATE AS days_remaining, -- positive = future
    CASE
        WHEN l.expiry_date < CURRENT_DATE
            THEN 'expired'
        WHEN l.expiry_date <= CURRENT_DATE + i.expiry_critical_days
            THEN 'critical'
        WHEN l.expiry_date <= CURRENT_DATE + i.expiry_warning_days
            THEN 'warning'
        ELSE 'ok'
    END AS expiry_status
FROM inventory_lots l
JOIN inventory_items    i ON l.inventory_item_id = i.id
LEFT JOIN branches      b ON l.branch_id = b.id
WHERE l.is_deleted = FALSE
  AND l.remaining_quantity > 0
  AND l.expiry_date IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- 6. Trigger: auto-updated updated_at on inventory_lots
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = CURRENT_TIMESTAMP; RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_inventory_lots_updated_at ON inventory_lots;
CREATE TRIGGER trg_inventory_lots_updated_at
    BEFORE UPDATE ON inventory_lots
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ────────────────────────────────────────────────────────────
-- Done.
-- ────────────────────────────────────────────────────────────
