-- Migration 004: Session Integrity & Order-Session Link
-- 
-- Fixes:
-- 1. Enforces one active session per table (partial unique index)
-- 2. Auto-updates restaurant_tables.status when session opens/closes
-- 3. Backfills session_token and guest_count on existing orders

-- =========================================================================
-- 1. Unique Index: One Active Session Per Table
-- =========================================================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_session_per_table
ON table_sessions (table_number, merchant_id)
WHERE is_active = 1;

-- =========================================================================
-- 2. Trigger: Auto-Sync restaurant_tables.status
-- =========================================================================
CREATE OR REPLACE FUNCTION sync_table_status_on_session_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.is_active = 1 THEN
        UPDATE restaurant_tables
        SET status = 'occupied', updated_at = NOW()
        WHERE table_number = NEW.table_number AND merchant_id = NEW.merchant_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.is_active = 0 AND OLD.is_active = 1 THEN
        UPDATE restaurant_tables
        SET status = 'vacant', updated_at = NOW()
        WHERE table_number = NEW.table_number AND merchant_id = NEW.merchant_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_table_status ON table_sessions;
CREATE TRIGGER trg_sync_table_status
AFTER INSERT OR UPDATE OF is_active ON table_sessions
FOR EACH ROW
EXECUTE FUNCTION sync_table_status_on_session_change();

-- =========================================================================
-- 3. Backfill existing data
-- =========================================================================
UPDATE orders
SET guest_count = 2
WHERE guest_count IS NULL OR guest_count = 0;

UPDATE orders o
SET session_token = s.session_token
FROM table_sessions s
WHERE o.table_number = s.table_number
  AND s.is_active = 1
  AND o.session_token IS NULL
  AND o.created_at >= s.created_at;

-- Fix orphaned session (table status = vacant but has active session)
UPDATE restaurant_tables t
SET status = 'occupied'
FROM table_sessions s
WHERE t.table_number = s.table_number
  AND s.is_active = 1
  AND t.status = 'vacant';