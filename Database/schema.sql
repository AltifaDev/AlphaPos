-- PostgreSQL Database Schema for AlphaPos (Multi-Tenant SaaS Version)
-- Aligned with iPad POS Client, iPhone Staff Client, and Customer Web App

-- Enable UUID extension if not already available
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- NOTE: Do NOT run DROP TABLE in production.
-- Use CREATE TABLE IF NOT EXISTS for idempotent migrations.
-- Drop statements are only for development reset.

-- =========================================================================
-- 1. TENANTS & MERCHANT USERS
-- =========================================================================

-- Merchants (Shops)
CREATE TABLE merchants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    currency VARCHAR(10) DEFAULT 'THB',
    kitchen_workflow_required BOOLEAN DEFAULT FALSE,
    website VARCHAR(255),
    address_street TEXT,
    tax_id VARCHAR(50),
    branch_code VARCHAR(50),
    tax_rate DECIMAL(5,2) DEFAULT 0.00,
    tax_type VARCHAR(20) DEFAULT 'exclusive',
    service_charge_rate DECIMAL(5,2) DEFAULT 0.00,
    receipt_header TEXT,
    receipt_footer TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Merchant Users (Dashboard & Backoffice Owners/Managers)
CREATE TABLE merchant_users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role VARCHAR(50) DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Restaurant Tables (Layout and Coordinates for Floor Plan)
CREATE TABLE restaurant_tables (
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
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_merchant_table_number UNIQUE (merchant_id, table_number)
);

-- Menu Items
CREATE TABLE menu_items (
    id TEXT PRIMARY KEY,
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category VARCHAR(50) NOT NULL,
    emoji VARCHAR(10),
    img_class VARCHAR(50),
    image_url TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Table Sessions (Supports table tracking without dynamic table CRUD)
CREATE TABLE table_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    table_number VARCHAR(10) NOT NULL,
    session_token VARCHAR(255) NOT NULL UNIQUE,
    is_active INTEGER NOT NULL DEFAULT 1, -- 1 = active, 0 = inactive
    guest_count INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE
);

-- Orders
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_number VARCHAR(20) NOT NULL,
    CONSTRAINT unique_merchant_order_number UNIQUE (merchant_id, order_number),
    table_number VARCHAR(10) NOT NULL,
    total DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) DEFAULT 'preparing', -- 'preparing', 'ready', 'served', 'completed', 'cancelled'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    delivery_brand VARCHAR(50),
    delivery_gp DECIMAL(5,2) DEFAULT 0.00,
    delivery_ad_fee DECIMAL(10,2) DEFAULT 0.00,
    delivery_ad_fee_is_pct BOOLEAN DEFAULT false,
    delivery_other_fee DECIMAL(10,2) DEFAULT 0.00
);

-- Order Items
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    item_name VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'cooking', -- 'cooking', 'preparing', 'ready', 'served'
    item_id TEXT, -- References menu_items(id) loosely
    branch_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Service Requests (Calls for Staff)
CREATE TABLE service_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    table_number VARCHAR(10) NOT NULL,
    request_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'completed'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Payments
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE RESTRICT,
    amount DECIMAL(10,2) NOT NULL,
    payment_method VARCHAR(30) NOT NULL, -- 'cash', 'credit_card', 'qr_promptpay'
    status VARCHAR(20) DEFAULT 'completed',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Employees
CREATE TABLE employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    phone VARCHAR(20),
    national_id VARCHAR(20),
    employment_type VARCHAR(20) NOT NULL, -- 'hourly', 'monthly'
    pay_rate DECIMAL(10,2) NOT NULL,
    username VARCHAR(50) NOT NULL,
    CONSTRAINT unique_merchant_username UNIQUE (merchant_id, username),
    pin_hash TEXT NOT NULL DEFAULT '', -- SHA256 hash of PIN (use bcrypt/argon2 in production)
    role VARCHAR(50) NOT NULL,
    resigned_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Timecards
CREATE TABLE timecards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE,
    employee_name VARCHAR(100) NOT NULL,
    clock_in TIMESTAMP WITH TIME ZONE NOT NULL,
    clock_out TIMESTAMP WITH TIME ZONE,
    break_duration INTEGER DEFAULT 0,
    overtime_minutes INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending_audit', -- 'approved', 'pending_audit', 'rejected'
    notes TEXT,
    clock_in_confidence DECIMAL(5,2),
    clock_out_confidence DECIMAL(5,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Promotions (Discounts and Special Offers)
CREATE TABLE promotions (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    title VARCHAR(200) NOT NULL,
    promo_description TEXT,
    image_data TEXT,
    media_type VARCHAR(20) DEFAULT 'image',
    is_active INTEGER DEFAULT 1,
    discount_type VARCHAR(30) DEFAULT 'none',
    discount_value DECIMAL(10,2) DEFAULT 0,
    minimum_spend DECIMAL(10,2) DEFAULT 0,
    applies_to_menu_item_id TEXT REFERENCES menu_items(id) ON DELETE SET NULL,
    reward_menu_item_id TEXT REFERENCES menu_items(id) ON DELETE SET NULL,
    required_quantity INTEGER DEFAULT 1,
    reward_quantity INTEGER DEFAULT 0,
    max_redemptions INTEGER,
    current_redemptions INTEGER DEFAULT 0,
    per_customer_limit INTEGER,
    starts_at TIMESTAMP WITH TIME ZONE,
    ends_at TIMESTAMP WITH TIME ZONE,
    is_deleted INTEGER DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Promotion Bundle Items (bundle_price component definitions)
CREATE TABLE promotion_bundle_items (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    promotion_id UUID REFERENCES promotions(id) ON DELETE CASCADE NOT NULL,
    menu_item_id TEXT REFERENCES menu_items(id) ON DELETE CASCADE NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1),
    display_order INTEGER NOT NULL DEFAULT 0,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Inventory Transactions (Stock tracking)
CREATE TABLE inventory_transactions (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    item_name VARCHAR(200) NOT NULL,
    quantity DECIMAL(10,2) NOT NULL,
    type VARCHAR(50) NOT NULL,
    item_id UUID,
    transaction_type VARCHAR(50),
    cost_price DECIMAL(10,2),
    reference_id UUID,
    notes TEXT,
    branch_id UUID,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 3. INDEXES FOR PERFORMANCE & ISOLATION JOINING
-- =========================================================================
CREATE INDEX idx_merchants_email ON merchants (email);
CREATE INDEX idx_merchant_users_merchant ON merchant_users (merchant_id);

CREATE INDEX idx_menu_items_merchant ON menu_items (merchant_id);
CREATE INDEX idx_table_sessions_merchant ON table_sessions (merchant_id);
CREATE INDEX idx_orders_merchant ON orders (merchant_id);
CREATE INDEX idx_order_items_merchant ON order_items (merchant_id);
CREATE INDEX idx_service_requests_merchant ON service_requests (merchant_id);
CREATE INDEX idx_payments_merchant ON payments (merchant_id);
CREATE INDEX idx_employees_merchant ON employees (merchant_id);
CREATE INDEX idx_timecards_merchant ON timecards (merchant_id);

CREATE INDEX idx_orders_table ON orders (table_number);
CREATE INDEX idx_table_sessions_active ON table_sessions (table_number, is_active);
CREATE INDEX idx_order_items_order ON order_items (order_id);
CREATE INDEX idx_payments_order ON payments (order_id);
CREATE INDEX idx_timecards_employee ON timecards (employee_id);
CREATE INDEX idx_orders_merchant_status ON orders (merchant_id, status);
CREATE INDEX idx_orders_merchant_table ON orders (merchant_id, table_number);
CREATE INDEX idx_promotions_merchant ON promotions (merchant_id);
CREATE INDEX idx_promotions_active ON promotions (is_active, is_deleted);
CREATE INDEX idx_promotions_product_rule ON promotions (merchant_id, applies_to_menu_item_id, is_active, is_deleted);
CREATE INDEX idx_promotions_effective ON promotions (merchant_id, is_active, is_deleted, starts_at, ends_at, current_redemptions);
CREATE INDEX idx_promotion_bundle_items_promotion ON promotion_bundle_items (promotion_id, display_order);
CREATE INDEX idx_inventory_transactions_merchant ON inventory_transactions (merchant_id);
CREATE INDEX idx_inventory_transactions_item_branch_time ON inventory_transactions (merchant_id, item_id, branch_id, updated_at DESC);
CREATE UNIQUE INDEX idx_inventory_transactions_reference_unique
    ON inventory_transactions (merchant_id, transaction_type, reference_id, item_id);

-- =========================================================================
-- 4. UTILITY HELPER FUNCTIONS
-- =========================================================================

-- Extract merchant_id from JWT claims only (Supabase Auth app_metadata or direct claim).
-- NOTE: HTTP header fallback has been REMOVED for security.
-- Accepting merchant_id from request headers allows anon users to impersonate any merchant.
-- Only the JWT token (which is cryptographically signed) should be trusted.
CREATE OR REPLACE FUNCTION get_merchant_id()
RETURNS UUID AS $$
DECLARE
    v_merchant_id TEXT;
    v_claims JSON;
BEGIN
    -- Attempt to read from JWT Claims
    BEGIN
        v_claims := current_setting('request.jwt.claims', true)::json;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;

    IF v_claims IS NULL THEN
        RETURN NULL;
    END IF;

    -- standard Supabase Auth app_metadata claim path
    v_merchant_id := v_claims->'app_metadata'->>'merchant_id';

    -- fallback direct claim path
    IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
        v_merchant_id := v_claims->>'merchant_id';
    END IF;

    RETURN NULLIF(v_merchant_id, '')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- Points to get_merchant_id() for backward compatibility
CREATE OR REPLACE FUNCTION get_active_merchant_id()
RETURNS UUID AS $$
BEGIN
    RETURN get_merchant_id();
END;
$$ LANGUAGE plpgsql STABLE;

-- =========================================================================
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- =========================================================================

-- Re-enable RLS on all tables
ALTER TABLE merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE merchant_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE timecards ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotion_bundle_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;

-- Define policies

CREATE POLICY "merchant_isolation_merchants" ON merchants
    FOR SELECT TO public USING (id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_merchants_delete" ON merchants
    FOR DELETE TO public USING (id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_merchants_insert" ON merchants
    FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "merchant_isolation_merchant_users" ON merchant_users
    FOR SELECT TO public USING (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_restaurant_tables" ON restaurant_tables
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_menu_items_select" ON menu_items
    FOR SELECT TO public USING (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_menu_items_insert" ON menu_items
    FOR INSERT TO anon WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_menu_items_update" ON menu_items
    FOR UPDATE TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_table_sessions" ON table_sessions
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_orders" ON orders
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_order_items" ON order_items
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_service_requests" ON service_requests
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_payments_select" ON payments
    FOR SELECT TO anon USING (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_payments_insert" ON payments
    FOR INSERT TO anon WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_employees" ON employees
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_timecards_select" ON timecards
    FOR SELECT TO anon USING (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_timecards_insert" ON timecards
    FOR INSERT TO anon WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_timecards_update" ON timecards
    FOR UPDATE TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_promotions" ON promotions
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_promotion_bundle_items" ON promotion_bundle_items
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_inventory_transactions" ON inventory_transactions
    FOR ALL TO anon USING (merchant_id = get_active_merchant_id()) WITH CHECK (merchant_id = get_active_merchant_id());

-- =========================================================================
-- 6. STORED PROCEDURES (RPCs)
-- =========================================================================

-- Stored procedure to complete order payment and close the table session atomically with merchant validation
CREATE OR REPLACE FUNCTION complete_checkout(
    p_payment_id UUID,
    p_order_id UUID,
    p_amount DECIMAL,
    p_method VARCHAR,
    p_table_number VARCHAR
) RETURNS VOID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID;
    v_caller_merchant_id UUID;
BEGIN
    -- Verify caller's merchant_id matches the order's merchant_id
    v_caller_merchant_id := get_merchant_id();

    SELECT merchant_id INTO v_merchant_id FROM orders WHERE id = p_order_id;

    IF v_merchant_id IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_caller_merchant_id IS DISTINCT FROM v_merchant_id THEN
        RAISE EXCEPTION 'Permission denied: merchant mismatch';
    END IF;

    -- 1. Insert payment record
    INSERT INTO payments (id, order_id, amount, payment_method, status, created_at, merchant_id)
    VALUES (p_payment_id, p_order_id, p_amount, p_method, 'completed', CURRENT_TIMESTAMP, v_merchant_id);

    -- 2. Close active session for that table
    UPDATE table_sessions
    SET is_active = 0, ended_at = CURRENT_TIMESTAMP
    WHERE table_number = p_table_number AND is_active = 1 AND merchant_id = v_merchant_id;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- 7. ONBOARDING TRIGGERS (Auto-Tenant Creation on Sign-Up)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.handle_new_merchant_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID;
    v_first_name TEXT;
    v_last_name TEXT;
BEGIN
    -- A. Create a new merchant profile for the registering owner
    INSERT INTO public.merchants (name, email)
    VALUES (
        COALESCE(new.raw_user_meta_data->>'store_name', 'My New POS Shop'),
        new.email
    )
    RETURNING id INTO v_merchant_id;

    -- B. Extract owner name from user metadata
    v_first_name := COALESCE(new.raw_user_meta_data->>'first_name', 'Owner');
    v_last_name := COALESCE(new.raw_user_meta_data->>'last_name', 'User');

    -- C. Link to merchant_users table (works in AFTER INSERT as auth.users row exists)
    INSERT INTO public.merchant_users (id, merchant_id, first_name, last_name, role)
    VALUES (new.id, v_merchant_id, v_first_name, v_last_name, 'owner');

    -- D. Inject merchant_id custom claim into app_metadata (raw_app_meta_data)
    UPDATE auth.users
    SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('merchant_id', v_merchant_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Bind the trigger to auth.users table as AFTER INSERT
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_merchant_user();
