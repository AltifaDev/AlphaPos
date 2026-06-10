-- migration_restaurant_tables.sql
-- Create restaurant_tables table for Online Multi-Tenant Table Sync

BEGIN;

-- 1. Create restaurant_tables table
CREATE TABLE IF NOT EXISTS restaurant_tables (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    table_number VARCHAR(50) NOT NULL,
    capacity INTEGER NOT NULL DEFAULT 2 CHECK (capacity > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'vacant',
    qr_code_identifier VARCHAR(255),
    position_x DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    position_y DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    floor INTEGER NOT NULL DEFAULT 1,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- Prevent duplicate table numbers for the same merchant
    CONSTRAINT unique_merchant_table_number UNIQUE (merchant_id, table_number)
);

-- Create performance indexes
CREATE INDEX IF NOT EXISTS idx_restaurant_tables_merchant ON restaurant_tables (merchant_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_tables_deleted ON restaurant_tables (is_deleted);

-- 2. Enable Row Level Security (RLS)
ALTER TABLE restaurant_tables ENABLE ROW LEVEL SECURITY;

-- 3. Define isolation policies based on merchant_id
DROP POLICY IF EXISTS "merchant_isolation_restaurant_tables" ON restaurant_tables;

CREATE POLICY "merchant_isolation_restaurant_tables" ON restaurant_tables
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

-- 4. Auto-update updated_at on row modification
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_restaurant_tables_updated_at ON restaurant_tables;
CREATE TRIGGER trg_restaurant_tables_updated_at
    BEFORE UPDATE ON restaurant_tables
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMIT;
