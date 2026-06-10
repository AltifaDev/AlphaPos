-- PostgreSQL SQL migration script to upgrade database to Multi-Tenant architecture
-- Enables RLS, creates merchants table, adds merchant_id column to operational tables,
-- associates existing records with a default merchant, and sets up tenant-isolated policies.

BEGIN;

-- 1. Create the Merchants (Tenants) table
CREATE TABLE IF NOT EXISTS merchants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    currency VARCHAR(10) DEFAULT 'THB',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 2. Insert the Default Seed Merchant and capture its ID
INSERT INTO merchants (name, email, phone, currency)
VALUES ('AlphaPos HQ', 'hq@alphapos.com', '02-123-4567', 'THB')
ON CONFLICT (email) DO NOTHING;

-- 3. Get the ID of the default merchant to use as fallback/seed
DO $$
DECLARE
    v_default_merchant_id UUID;
    v_table_name RECORD;
BEGIN
    SELECT id INTO v_default_merchant_id FROM merchants WHERE email = 'hq@alphapos.com';
    
    -- 4. Add merchant_id column to core operational tables if they don't exist yet
    -- We append the column as nullable first, populate it with the default ID, then make it NOT NULL
    FOR v_table_name IN 
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_name IN ('employees', 'menu_items', 'table_sessions', 'orders', 'order_items', 'payments', 'service_requests', 'timecards')
    LOOP
        -- Check and Add column
        IF NOT EXISTS (
            SELECT 1 
            FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = v_table_name.table_name 
              AND column_name = 'merchant_id'
        ) THEN
            EXECUTE format('ALTER TABLE %I ADD COLUMN merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE', v_table_name.table_name);
            
            -- Populate column with default merchant ID
            EXECUTE format('UPDATE %I SET merchant_id = %L', v_table_name.table_name, v_default_merchant_id);
            
            -- Set to NOT NULL
            EXECUTE format('ALTER TABLE %I ALTER COLUMN merchant_id SET NOT NULL', v_table_name.table_name);
            
            -- Create performance index on merchant_id
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (merchant_id)', 'idx_' || v_table_name.table_name || '_merchant', v_table_name.table_name);
        END IF;
    END LOOP;
END;
$$;

-- 5. Helper function to extract merchant_id from JWT claims or HTTP request headers
CREATE OR REPLACE FUNCTION get_active_merchant_id() 
RETURNS UUID AS $$
DECLARE
    v_merchant_id TEXT;
BEGIN
    -- A. Attempt to read from JWT Custom Claim (configured during Device activation/owner JWT)
    v_merchant_id := current_setting('request.jwt.claims', true)::json->>'merchant_id';
    
    -- B. Fallback to custom HTTP header 'x-merchant-id' (useful for anonymous REST requests)
    IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
        v_merchant_id := current_setting('request.headers', true)::json->>'x-merchant-id';
    END IF;
    
    RETURN NULLIF(v_merchant_id, '')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- 6. Update Row Level Security (RLS) Policies to enforce tenant isolation
-- Drop old policies to avoid conflict
DROP POLICY IF EXISTS "Allow public read-only access to menu_items" ON menu_items;
DROP POLICY IF EXISTS "Allow anon read-write access to table_sessions" ON table_sessions;
DROP POLICY IF EXISTS "Allow anon read-write access to orders" ON orders;
DROP POLICY IF EXISTS "Allow anon read-write access to order_items" ON order_items;
DROP POLICY IF EXISTS "Allow anon read-write access to service_requests" ON service_requests;
DROP POLICY IF EXISTS "Allow anon read-insert access to payments" ON payments;
DROP POLICY IF EXISTS "Allow anon read-only access to employees" ON employees;
DROP POLICY IF EXISTS "Allow anon read-write access to timecards" ON timecards;

DROP POLICY IF EXISTS "merchant_isolation_merchants" ON merchants;
DROP POLICY IF EXISTS "merchant_isolation_menu_items" ON menu_items;
DROP POLICY IF EXISTS "merchant_isolation_table_sessions" ON table_sessions;
DROP POLICY IF EXISTS "merchant_isolation_orders" ON orders;
DROP POLICY IF EXISTS "merchant_isolation_order_items" ON order_items;
DROP POLICY IF EXISTS "merchant_isolation_service_requests" ON service_requests;
DROP POLICY IF EXISTS "merchant_isolation_payments" ON payments;
DROP POLICY IF EXISTS "merchant_isolation_payments_select" ON payments;
DROP POLICY IF EXISTS "merchant_isolation_payments_insert" ON payments;
DROP POLICY IF EXISTS "merchant_isolation_employees" ON employees;
DROP POLICY IF EXISTS "merchant_isolation_timecards" ON timecards;
DROP POLICY IF EXISTS "merchant_isolation_timecards_select" ON timecards;
DROP POLICY IF EXISTS "merchant_isolation_timecards_insert" ON timecards;
DROP POLICY IF EXISTS "merchant_isolation_timecards_update" ON timecards;

-- Re-enable RLS on all tables
ALTER TABLE merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE timecards ENABLE ROW LEVEL SECURITY;

-- Define tenant-isolated policies:
-- Only rows matching get_active_merchant_id() can be accessed/modified

-- Merchants table: Users can view their own merchant row
CREATE POLICY "merchant_isolation_merchants" ON merchants
    FOR SELECT TO public USING (id = get_active_merchant_id());

-- Menu Items: Public/Anon reads within the active merchant; only admins can edit
CREATE POLICY "merchant_isolation_menu_items" ON menu_items
    FOR SELECT TO public USING (merchant_id = get_active_merchant_id());

-- Table Sessions: Scoped read-write
CREATE POLICY "merchant_isolation_table_sessions" ON table_sessions
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

-- Orders: Scoped read-write
CREATE POLICY "merchant_isolation_orders" ON orders
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

-- Order Items: Scoped read-write
CREATE POLICY "merchant_isolation_order_items" ON order_items
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

-- Service Requests: Scoped read-write
CREATE POLICY "merchant_isolation_service_requests" ON service_requests
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

-- Payments: Scoped insert-read, block edit/delete
CREATE POLICY "merchant_isolation_payments_select" ON payments
    FOR SELECT TO anon USING (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_payments_insert" ON payments
    FOR INSERT TO anon WITH CHECK (merchant_id = get_active_merchant_id());

-- Employees: Scoped reads
CREATE POLICY "merchant_isolation_employees" ON employees
    FOR SELECT TO anon USING (merchant_id = get_active_merchant_id());

-- Timecards: Scoped read, insert, update
CREATE POLICY "merchant_isolation_timecards_select" ON timecards
    FOR SELECT TO anon USING (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_timecards_insert" ON timecards
    FOR INSERT TO anon WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_timecards_update" ON timecards
    FOR UPDATE TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

COMMIT;
