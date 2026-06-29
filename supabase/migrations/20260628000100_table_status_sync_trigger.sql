-- Migration: table_status_sync_trigger
-- Date: 2026-06-28
-- Description: Trigger to keep restaurant_tables.status in sync with table_sessions.is_active changes

CREATE OR REPLACE FUNCTION sync_table_status_from_session()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF NEW.is_active = 1 THEN
            UPDATE restaurant_tables
            SET status = 'occupied', updated_at = CURRENT_TIMESTAMP
            WHERE table_number = NEW.table_number AND merchant_id = NEW.merchant_id;
        END IF;
    ELSIF (TG_OP = 'UPDATE') THEN
        -- If it transitioned to active
        IF NEW.is_active = 1 AND (OLD.is_active IS NULL OR OLD.is_active = 0) THEN
            UPDATE restaurant_tables
            SET status = 'occupied', updated_at = CURRENT_TIMESTAMP
            WHERE table_number = NEW.table_number AND merchant_id = NEW.merchant_id;
        -- If it transitioned to inactive
        ELSIF (NEW.is_active = 0 OR NEW.is_active IS NULL) AND OLD.is_active = 1 THEN
            -- Only set to vacant if current status is occupied (to avoid overriding 'cleaning' status set by checkout)
            UPDATE restaurant_tables
            SET status = 'vacant', updated_at = CURRENT_TIMESTAMP
            WHERE table_number = NEW.table_number AND merchant_id = NEW.merchant_id AND status = 'occupied';
        END IF;
    ELSIF (TG_OP = 'DELETE') THEN
        IF OLD.is_active = 1 THEN
            UPDATE restaurant_tables
            SET status = 'vacant', updated_at = CURRENT_TIMESTAMP
            WHERE table_number = OLD.table_number AND merchant_id = OLD.merchant_id AND status = 'occupied';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_table_status_from_session ON table_sessions;
CREATE TRIGGER trg_sync_table_status_from_session
    AFTER INSERT OR UPDATE OR DELETE
    ON table_sessions
    FOR EACH ROW
    EXECUTE FUNCTION sync_table_status_from_session();
