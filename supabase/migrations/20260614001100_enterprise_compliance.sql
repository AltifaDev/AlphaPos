-- =========================================================================
-- Migration 009: Enterprise Compliance & Financial Features
-- Created: 2026-06-14
-- Description: Creates tables for customers, discounts, tax lines, tips,
--              refunds, cash movements, loyalty, gift cards, void reasons,
--              and receipt logging. Adds columns to orders and payments.
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. CUSTOMERS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(200) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(50),
    tax_id VARCHAR(50),
    address TEXT,
    loyalty_points INTEGER DEFAULT 0,
    membership_tier VARCHAR(50) DEFAULT 'standard',
    total_spend DECIMAL(12,2) DEFAULT 0.00,
    visit_count INTEGER DEFAULT 0,
    notes TEXT,
    date_of_birth DATE,
    allergies TEXT,
    preferences TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 2. ORDER DISCOUNTS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.order_discounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    promotion_id UUID,
    discount_type VARCHAR(30) NOT NULL, -- 'percentage', 'fixed', 'item_level'
    discount_value DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) NOT NULL, -- actual amount deducted
    reason TEXT,
    applied_by_employee_id UUID,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 3. ORDER TAX LINES
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.order_tax_lines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    tax_name VARCHAR(100) NOT NULL, -- e.g., 'VAT 7%', 'Service Tax'
    tax_rate DECIMAL(5,2) NOT NULL,
    taxable_amount DECIMAL(10,2) NOT NULL,
    tax_amount DECIMAL(10,2) NOT NULL,
    is_inclusive BOOLEAN DEFAULT TRUE,
    jurisdiction VARCHAR(100),
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 4. TIPS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.tips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
    amount DECIMAL(10,2) NOT NULL,
    tip_type VARCHAR(30) DEFAULT 'manual', -- 'manual', 'percentage', 'round_up'
    employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 5. REFUND TRANSACTIONS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.refund_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    original_payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
    refund_amount DECIMAL(10,2) NOT NULL,
    refund_method VARCHAR(30) NOT NULL, -- 'cash', 'original_tender', 'store_credit'
    reason_code VARCHAR(50) NOT NULL, -- 'customer_request', 'defective', 'wrong_order', 'overcharge'
    reason_notes TEXT,
    refunded_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    approved_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    status VARCHAR(20) DEFAULT 'completed', -- 'pending_approval', 'completed', 'rejected'
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 6. CASH MOVEMENTS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.cash_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    register_session_id UUID,
    movement_type VARCHAR(30) NOT NULL, -- 'cash_in', 'cash_out', 'paid_in', 'paid_out'
    amount DECIMAL(10,2) NOT NULL,
    reason TEXT NOT NULL,
    performed_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 7. LOYALTY TRANSACTIONS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    transaction_type VARCHAR(30) NOT NULL, -- 'earn', 'redeem', 'adjust', 'expire'
    points INTEGER NOT NULL,
    points_balance_after INTEGER NOT NULL,
    description TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 8. GIFT CARDS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.gift_cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    card_number VARCHAR(50) UNIQUE NOT NULL,
    balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    initial_value DECIMAL(10,2) NOT NULL,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'exhausted', 'expired', 'disabled'
    expires_at TIMESTAMP WITH TIME ZONE,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 9. VOID REASONS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.void_reasons (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    code VARCHAR(50) NOT NULL,
    description VARCHAR(200) NOT NULL,
    requires_manager_approval BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 10. RECEIPT LOGS
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.receipt_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    receipt_number VARCHAR(50) NOT NULL,
    receipt_type VARCHAR(30) DEFAULT 'sale', -- 'sale', 'refund', 'void', 'reprint'
    printed_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    printed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 11. AUDIT LOGS (idempotent – may already exist from migration 011)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    action_type VARCHAR(100) NOT NULL,
    details TEXT,
    original_value DECIMAL(10,2),
    new_value DECIMAL(10,2),
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- =========================================================================
-- 12. REGISTER SESSIONS (idempotent – may already exist from migration 012)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.register_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    opened_by_user_id UUID NOT NULL,
    closed_by_user_id UUID,
    opened_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,
    opening_cash DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    expected_closing_cash DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    actual_closing_cash DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    cash_discrepancy DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    notes TEXT,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- =========================================================================
-- ROW LEVEL SECURITY
-- =========================================================================
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_tax_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gift_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.void_reasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.register_sessions ENABLE ROW LEVEL SECURITY;


-- =========================================================================
-- RLS POLICIES (DROP IF EXISTS + CREATE to be idempotent)
-- =========================================================================

-- customers
DROP POLICY IF EXISTS "merchant_isolation_customers" ON public.customers;
CREATE POLICY "merchant_isolation_customers" ON public.customers
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- order_discounts
DROP POLICY IF EXISTS "merchant_isolation_order_discounts" ON public.order_discounts;
CREATE POLICY "merchant_isolation_order_discounts" ON public.order_discounts
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- order_tax_lines
DROP POLICY IF EXISTS "merchant_isolation_order_tax_lines" ON public.order_tax_lines;
CREATE POLICY "merchant_isolation_order_tax_lines" ON public.order_tax_lines
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- tips
DROP POLICY IF EXISTS "merchant_isolation_tips" ON public.tips;
CREATE POLICY "merchant_isolation_tips" ON public.tips
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- refund_transactions
DROP POLICY IF EXISTS "merchant_isolation_refund_transactions" ON public.refund_transactions;
CREATE POLICY "merchant_isolation_refund_transactions" ON public.refund_transactions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- cash_movements
DROP POLICY IF EXISTS "merchant_isolation_cash_movements" ON public.cash_movements;
CREATE POLICY "merchant_isolation_cash_movements" ON public.cash_movements
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- loyalty_transactions
DROP POLICY IF EXISTS "merchant_isolation_loyalty_transactions" ON public.loyalty_transactions;
CREATE POLICY "merchant_isolation_loyalty_transactions" ON public.loyalty_transactions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- gift_cards
DROP POLICY IF EXISTS "merchant_isolation_gift_cards" ON public.gift_cards;
CREATE POLICY "merchant_isolation_gift_cards" ON public.gift_cards
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- void_reasons
DROP POLICY IF EXISTS "merchant_isolation_void_reasons" ON public.void_reasons;
CREATE POLICY "merchant_isolation_void_reasons" ON public.void_reasons
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- receipt_logs
DROP POLICY IF EXISTS "merchant_isolation_receipt_logs" ON public.receipt_logs;
CREATE POLICY "merchant_isolation_receipt_logs" ON public.receipt_logs
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- audit_logs (idempotent – policy may exist from migration 011)
DROP POLICY IF EXISTS "merchant_isolation_audit_logs" ON public.audit_logs;
CREATE POLICY "merchant_isolation_audit_logs" ON public.audit_logs
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- register_sessions (idempotent – policy may exist from migration 012)
DROP POLICY IF EXISTS "merchant_isolation_register_sessions" ON public.register_sessions;
CREATE POLICY "merchant_isolation_register_sessions" ON public.register_sessions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());


-- =========================================================================
-- INDEXES ON merchant_id
-- =========================================================================
CREATE INDEX IF NOT EXISTS idx_customers_merchant ON public.customers (merchant_id);
CREATE INDEX IF NOT EXISTS idx_order_discounts_merchant ON public.order_discounts (merchant_id);
CREATE INDEX IF NOT EXISTS idx_order_tax_lines_merchant ON public.order_tax_lines (merchant_id);
CREATE INDEX IF NOT EXISTS idx_tips_merchant ON public.tips (merchant_id);
CREATE INDEX IF NOT EXISTS idx_refund_transactions_merchant ON public.refund_transactions (merchant_id);
CREATE INDEX IF NOT EXISTS idx_cash_movements_merchant ON public.cash_movements (merchant_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_merchant ON public.loyalty_transactions (merchant_id);
CREATE INDEX IF NOT EXISTS idx_gift_cards_merchant ON public.gift_cards (merchant_id);
CREATE INDEX IF NOT EXISTS idx_void_reasons_merchant ON public.void_reasons (merchant_id);
CREATE INDEX IF NOT EXISTS idx_receipt_logs_merchant ON public.receipt_logs (merchant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_merchant ON public.audit_logs (merchant_id);
CREATE INDEX IF NOT EXISTS idx_register_sessions_merchant ON public.register_sessions (merchant_id);

-- Additional useful indexes
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers (merchant_id, email);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON public.customers (merchant_id, phone);
CREATE INDEX IF NOT EXISTS idx_order_discounts_order ON public.order_discounts (order_id);
CREATE INDEX IF NOT EXISTS idx_order_tax_lines_order ON public.order_tax_lines (order_id);
CREATE INDEX IF NOT EXISTS idx_tips_order ON public.tips (order_id);
CREATE INDEX IF NOT EXISTS idx_refund_transactions_order ON public.refund_transactions (order_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_customer ON public.loyalty_transactions (customer_id);
CREATE INDEX IF NOT EXISTS idx_gift_cards_card_number ON public.gift_cards (card_number);
CREATE INDEX IF NOT EXISTS idx_gift_cards_customer ON public.gift_cards (customer_id);
CREATE INDEX IF NOT EXISTS idx_receipt_logs_order ON public.receipt_logs (order_id);
CREATE INDEX IF NOT EXISTS idx_cash_movements_session ON public.cash_movements (register_session_id);


-- =========================================================================
-- ALTER EXISTING TABLES
-- =========================================================================

-- orders: add customer_id, held_at, receipt_number
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS held_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS receipt_number VARCHAR(50);

-- payments: add tip_amount, updated_at
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS tip_amount DECIMAL(10,2) DEFAULT 0.00;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Index on orders.customer_id for lookups
CREATE INDEX IF NOT EXISTS idx_orders_customer ON public.orders (customer_id);


-- =========================================================================
-- FIX FK on order_items: item_id -> menu_items(id)
-- =========================================================================
DO $$ BEGIN
    ALTER TABLE public.order_items
        ADD CONSTRAINT fk_order_items_menu_item
        FOREIGN KEY (item_id) REFERENCES menu_items(id) ON DELETE SET NULL;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;


COMMIT;
