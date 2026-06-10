-- =========================================================================
-- Migration 001: Initial Schema
-- Created: 2026-06-09
-- Description: Base tables for AlphaPos multi-tenant POS system.
--              Covers customer web app, restaurant tables, orders, payments,
--              employees, timecards, promotions, and inventory transactions.
-- Status: APPLIED to Supabase (sdmtkixrqkmwcpwoisrg)
-- =========================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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
