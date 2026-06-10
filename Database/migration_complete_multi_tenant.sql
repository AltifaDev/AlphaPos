-- PostgreSQL SQL migration script to complete database multi-tenant migration
-- Adds merchant_id column to the remaining 17 tables, enables RLS,
-- and configures tenant-isolated row policies.

BEGIN;

DO $$
DECLARE
    v_table_name RECORD;
    v_default_merchant_id UUID;
BEGIN
    SELECT id INTO v_default_merchant_id FROM merchants WHERE email = 'hq@alphapos.com';

    -- Loop and add merchant_id column to the remaining 17 tables
    FOR v_table_name IN 
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_name IN (
            'tables', 'suppliers', 'inventory_items', 'inventory_transactions', 
            'categories', 'recipes', 'modifier_groups', 'menu_item_modifier_groups', 
            'modifiers', 'order_item_modifiers', 'register_sessions', 'employee_shifts', 
            'payroll_periods', 'payroll_slips', 'roles', 'users', 'user_sessions'
          )
    LOOP
        IF NOT EXISTS (
            SELECT 1 
            FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = v_table_name.table_name 
              AND column_name = 'merchant_id'
        ) THEN
            EXECUTE format('ALTER TABLE %I ADD COLUMN merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE', v_table_name.table_name);
            
            -- Update existing rows with default merchant
            EXECUTE format('UPDATE %I SET merchant_id = $1 WHERE merchant_id IS NULL', v_table_name.table_name) USING v_default_merchant_id;
            
            -- Set NOT NULL after populating existing rows
            EXECUTE format('ALTER TABLE %I ALTER COLUMN merchant_id SET NOT NULL', v_table_name.table_name);
            
            -- Create index
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (merchant_id)', 'idx_' || v_table_name.table_name || '_merchant', v_table_name.table_name);
        END IF;
    END LOOP;
END;
$$;

-- Enable RLS and define Policies for the 17 tables
DO $$
DECLARE
    v_table_name RECORD;
BEGIN
    FOR v_table_name IN 
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_name IN (
            'tables', 'suppliers', 'inventory_items', 'inventory_transactions', 
            'categories', 'recipes', 'modifier_groups', 'menu_item_modifier_groups', 
            'modifiers', 'order_item_modifiers', 'register_sessions', 'employee_shifts', 
            'payroll_periods', 'payroll_slips', 'roles', 'users', 'user_sessions'
          )
    LOOP
        -- Enable RLS
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_table_name.table_name);
        
        -- Drop old isolation policies if exist
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'merchant_isolation_' || v_table_name.table_name, v_table_name.table_name);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'Allow public read-only access to ' || v_table_name.table_name, v_table_name.table_name);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'Allow anon read-write access to ' || v_table_name.table_name, v_table_name.table_name);
        
        -- Create new tenant isolation policy
        EXECUTE format('
            CREATE POLICY %I ON %I
                FOR ALL 
                USING (merchant_id = public.get_active_merchant_id()) 
                WITH CHECK (merchant_id = public.get_active_merchant_id())
        ', 'merchant_isolation_' || v_table_name.table_name, v_table_name.table_name);
    END LOOP;
END;
$$;

COMMIT;
