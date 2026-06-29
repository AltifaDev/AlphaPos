-- =========================================================================
-- Migration 001: Initial Schema
-- Created: 2026-06-09
-- Description: Base tables for AlphaPos multi-tenant POS system.
--              Covers customer web app, restaurant tables, orders, payments,
--              employees, timecards, promotions, and inventory transactions.
-- Status: APPLIED to Supabase (your-project-ref)
-- =========================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================================================================
-- 0. Multi-Tenancy Helper Functions
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_merchant_id() 
RETURNS UUID AS $$
DECLARE
    v_merchant_id TEXT;
    v_claims JSON;
BEGIN
    -- A. Attempt to read from JWT Claims
    BEGIN
        v_claims := current_setting('request.jwt.claims', true)::json;
    EXCEPTION WHEN OTHERS THEN
        v_claims := NULL;
    END;

    IF v_claims IS NOT NULL THEN
        -- standard Supabase Auth app_metadata claim path
        v_merchant_id := v_claims->'app_metadata'->>'merchant_id';
        
        -- fallback direct claim path
        IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
            v_merchant_id := v_claims->>'merchant_id';
        END IF;
    END IF;
    
    -- B. Fallback to custom HTTP request header
    IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
        BEGIN
            v_merchant_id := current_setting('request.headers', true)::json->>'x-merchant-id';
        EXCEPTION WHEN OTHERS THEN
            v_merchant_id := NULL;
        END;
    END IF;
    
    RETURN NULLIF(v_merchant_id, '')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION public.get_active_merchant_id() 
RETURNS UUID AS $$
BEGIN
    RETURN public.get_merchant_id();
END;
$$ LANGUAGE plpgsql STABLE;


-- Merchants (Shop/Tenant root)
CREATE TABLE IF NOT EXISTS public.merchants (
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

-- Merchant Users (Dashboard/Backoffice Owners)
CREATE TABLE IF NOT EXISTS public.merchant_users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role VARCHAR(50) DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Branches (Physical locations)
CREATE TABLE IF NOT EXISTS public.branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(255) NOT NULL,
    branch_code VARCHAR(50) NOT NULL DEFAULT '00000',
    phone VARCHAR(50),
    website VARCHAR(255),
    logo_url TEXT,
    address_street TEXT,
    address_city VARCHAR(100),
    address_province VARCHAR(100),
    address_postal_code VARCHAR(20),
    address_country VARCHAR(100) DEFAULT 'Thailand',
    tax_id VARCHAR(50),
    tax_rate DECIMAL(5,2) DEFAULT 7.00,
    tax_type VARCHAR(20) DEFAULT 'inclusive',
    service_charge_rate DECIMAL(5,2) DEFAULT 0.00,
    currency VARCHAR(10) DEFAULT 'THB',
    receipt_header TEXT,
    receipt_footer TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Restaurant Tables
CREATE TABLE IF NOT EXISTS public.restaurant_tables (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
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
CREATE TABLE IF NOT EXISTS public.menu_items (
    id TEXT PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
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

-- Table Sessions
CREATE TABLE IF NOT EXISTS public.table_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    table_number VARCHAR(10) NOT NULL,
    session_token VARCHAR(255) NOT NULL UNIQUE,
    is_active INTEGER NOT NULL DEFAULT 1,
    guest_count INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE
);

-- Orders
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    order_number VARCHAR(20) UNIQUE NOT NULL,
    table_number VARCHAR(10) NOT NULL,
    total DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) DEFAULT 'preparing',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    delivery_brand VARCHAR(50),
    delivery_gp DECIMAL(5,2) DEFAULT 0.00,
    delivery_ad_fee DECIMAL(10,2) DEFAULT 0.00,
    delivery_ad_fee_is_pct BOOLEAN DEFAULT false,
    delivery_other_fee DECIMAL(10,2) DEFAULT 0.00
);

-- Order Items
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
    item_name VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'cooking',
    item_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Service Requests
CREATE TABLE IF NOT EXISTS public.service_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    table_number VARCHAR(10) NOT NULL,
    request_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Payments
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
    amount DECIMAL(10,2) NOT NULL,
    payment_method VARCHAR(30) NOT NULL,
    status VARCHAR(20) DEFAULT 'completed',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Employees
CREATE TABLE IF NOT EXISTS public.employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    phone VARCHAR(20),
    national_id VARCHAR(20),
    employment_type VARCHAR(20) NOT NULL,
    pay_rate DECIMAL(10,2) NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    pin_code VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL,
    resigned_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Timecards
CREATE TABLE IF NOT EXISTS public.timecards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    employee_id UUID REFERENCES public.employees(id) ON DELETE CASCADE,
    employee_name VARCHAR(100) NOT NULL,
    clock_in TIMESTAMP WITH TIME ZONE NOT NULL,
    clock_out TIMESTAMP WITH TIME ZONE,
    break_duration INTEGER DEFAULT 0,
    overtime_minutes INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending_audit',
    notes TEXT,
    clock_in_confidence DECIMAL(5,2),
    clock_out_confidence DECIMAL(5,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Promotions
CREATE TABLE IF NOT EXISTS public.promotions (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    title VARCHAR(200) NOT NULL,
    promo_description TEXT,
    image_data TEXT,
    is_active INTEGER DEFAULT 1,
    is_deleted INTEGER DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Inventory Transactions
CREATE TABLE IF NOT EXISTS public.inventory_transactions (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    item_name VARCHAR(200) NOT NULL,
    quantity DECIMAL(10,2) NOT NULL,
    type VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- 1. roles
CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_roles" ON public.roles
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_roles_merchant ON public.roles (merchant_id);

-- 2. users
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    password_hash VARCHAR(255) NOT NULL,
    pin_code_hash VARCHAR(255),
    role_id UUID REFERENCES public.roles(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_users" ON public.users
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_users_merchant ON public.users (merchant_id);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users (role_id);

-- 3. user_sessions
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    token VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_user_sessions" ON public.user_sessions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_user_sessions_merchant ON public.user_sessions (merchant_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON public.user_sessions (user_id);

-- 4. tables
CREATE TABLE IF NOT EXISTS public.tables (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    table_number VARCHAR(255) NOT NULL,
    capacity INTEGER NOT NULL DEFAULT 4,
    status VARCHAR(255) DEFAULT 'vacant',
    qr_code_identifier VARCHAR(255),
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.tables ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_tables" ON public.tables
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_tables_merchant ON public.tables (merchant_id);

-- 5. suppliers
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(255) NOT NULL,
    contact_name VARCHAR(255),
    phone VARCHAR(255),
    email VARCHAR(255),
    address TEXT,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_suppliers" ON public.suppliers
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_suppliers_merchant ON public.suppliers (merchant_id);

-- 6. inventory_items
CREATE TABLE IF NOT EXISTS public.inventory_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(255),
    unit VARCHAR(255) NOT NULL,
    current_quantity NUMERIC NOT NULL DEFAULT 0.0000,
    reorder_level NUMERIC NOT NULL DEFAULT 0.0000,
    cost_price NUMERIC NOT NULL DEFAULT 0.00,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_inventory_items" ON public.inventory_items
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_inventory_items_merchant ON public.inventory_items (merchant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_items_supplier ON public.inventory_items (supplier_id);

-- 7. categories
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    image_url TEXT,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_categories" ON public.categories
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_categories_merchant ON public.categories (merchant_id);

-- 8. recipes
CREATE TABLE IF NOT EXISTS public.recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    menu_item_id UUID,
    inventory_item_id UUID REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    quantity_required NUMERIC NOT NULL,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.recipes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_recipes" ON public.recipes
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_recipes_merchant ON public.recipes (merchant_id);
CREATE INDEX IF NOT EXISTS idx_recipes_inventory ON public.recipes (inventory_item_id);

-- 9. modifier_groups
CREATE TABLE IF NOT EXISTS public.modifier_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(255) NOT NULL,
    min_selection INTEGER DEFAULT 0,
    max_selection INTEGER DEFAULT 1,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.modifier_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_modifier_groups" ON public.modifier_groups
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_modifier_groups_merchant ON public.modifier_groups (merchant_id);

-- 10. menu_item_modifier_groups
CREATE TABLE IF NOT EXISTS public.menu_item_modifier_groups (
    menu_item_id TEXT NOT NULL,
    modifier_group_id UUID REFERENCES public.modifier_groups(id) ON DELETE CASCADE NOT NULL,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    PRIMARY KEY (menu_item_id, modifier_group_id)
);

ALTER TABLE public.menu_item_modifier_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_menu_item_modifier_groups" ON public.menu_item_modifier_groups
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_menu_item_mod_group_merchant ON public.menu_item_modifier_groups (merchant_id);

-- 11. modifiers
CREATE TABLE IF NOT EXISTS public.modifiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    modifier_group_id UUID REFERENCES public.modifier_groups(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    extra_price NUMERIC DEFAULT 0.00,
    inventory_item_id UUID REFERENCES public.inventory_items(id) ON DELETE SET NULL,
    quantity_required NUMERIC,
    is_available BOOLEAN DEFAULT TRUE,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.modifiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_modifiers" ON public.modifiers
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_modifiers_merchant ON public.modifiers (merchant_id);
CREATE INDEX IF NOT EXISTS idx_modifiers_group ON public.modifiers (modifier_group_id);

-- 12. order_item_modifiers
CREATE TABLE IF NOT EXISTS public.order_item_modifiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    order_item_id UUID,
    modifier_id UUID REFERENCES public.modifiers(id) ON DELETE CASCADE,
    price NUMERIC NOT NULL DEFAULT 0.00,
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.order_item_modifiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_order_item_modifiers" ON public.order_item_modifiers
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_order_item_mods_merchant ON public.order_item_modifiers (merchant_id);
CREATE INDEX IF NOT EXISTS idx_order_item_mods_modifier ON public.order_item_modifiers (modifier_id);

-- 13. employee_shifts
-- Note: merchant_id, is_synced, is_deleted, updated_at, and RLS will be added by Migration 008
CREATE TABLE IF NOT EXISTS public.employee_shifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES public.employees(id) ON DELETE CASCADE,
    scheduled_start TIMESTAMP WITH TIME ZONE NOT NULL,
    scheduled_end TIMESTAMP WITH TIME ZONE NOT NULL,
    role VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_employee_shifts_employee_base ON public.employee_shifts (employee_id);

-- 14. payroll_periods
CREATE TABLE IF NOT EXISTS public.payroll_periods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    payment_date DATE,
    status VARCHAR(255) DEFAULT 'draft',
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_payroll_periods" ON public.payroll_periods
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_payroll_periods_merchant ON public.payroll_periods (merchant_id);

-- 15. payroll_slips
CREATE TABLE IF NOT EXISTS public.payroll_slips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    payroll_period_id UUID REFERENCES public.payroll_periods(id) ON DELETE CASCADE,
    employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    total_hours_worked NUMERIC DEFAULT 0.00,
    base_pay NUMERIC NOT NULL,
    overtime_pay NUMERIC DEFAULT 0.00,
    bonus_pay NUMERIC DEFAULT 0.00,
    deductions NUMERIC DEFAULT 0.00,
    net_pay NUMERIC NOT NULL,
    payment_status VARCHAR(255) DEFAULT 'pending',
    transaction_ref VARCHAR(255),
    is_synced BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.payroll_slips ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_payroll_slips" ON public.payroll_slips
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_payroll_slips_merchant ON public.payroll_slips (merchant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_slips_period ON public.payroll_slips (payroll_period_id);
CREATE INDEX IF NOT EXISTS idx_payroll_slips_employee ON public.payroll_slips (employee_id);
