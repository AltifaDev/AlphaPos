-- =========================================================================
-- Migration 022: Enterprise Features (Missing Features)
-- Created: 2026-06-17
-- Description: Adds Shift Reports (Z-Reports/X-Reports), Advanced Tax Engine,
--              Receipt Templates, and Multi-Currency support.
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. ADVANCED TAX ENGINE
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.tax_rates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(100) NOT NULL,
    rate_percentage DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    tax_type VARCHAR(20) NOT NULL DEFAULT 'exclusive', -- 'exclusive', 'inclusive'
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_merchant_tax_name UNIQUE (merchant_id, name)
);

ALTER TABLE public.tax_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_tax_rates" ON public.tax_rates
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_tax_rates_merchant ON public.tax_rates (merchant_id, is_active, is_deleted);

-- Add is_tax_exempt to customers
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS is_tax_exempt BOOLEAN NOT NULL DEFAULT FALSE;


-- =========================================================================
-- 2. SHIFT REPORTS (Z-REPORTS & X-REPORTS)
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.shift_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    register_session_id UUID REFERENCES register_sessions(id) ON DELETE SET NULL,
    report_type VARCHAR(20) NOT NULL DEFAULT 'Z', -- 'X' (mid-shift), 'Z' (end-of-day)
    gross_sales DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    net_sales DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_tax DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_discounts DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_refunds DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    cash_expected DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    cash_actual DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    over_short DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    generated_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.shift_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_shift_reports" ON public.shift_reports
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_shift_reports_merchant ON public.shift_reports (merchant_id, created_at DESC);


-- =========================================================================
-- 3. RECEIPT TEMPLATES
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.receipt_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(100) NOT NULL,
    header_text TEXT,
    footer_text TEXT,
    logo_url TEXT,
    show_tax_id BOOLEAN NOT NULL DEFAULT TRUE,
    show_customer_info BOOLEAN NOT NULL DEFAULT TRUE,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.receipt_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_receipt_templates" ON public.receipt_templates
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_receipt_templates_merchant ON public.receipt_templates (merchant_id);


-- =========================================================================
-- 4. MULTI-CURRENCY SUPPORT (CURRENCY EXCHANGE RATES)
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.currency_exchange_rates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    base_currency VARCHAR(10) NOT NULL DEFAULT 'THB',
    target_currency VARCHAR(10) NOT NULL,
    exchange_rate DECIMAL(15,6) NOT NULL,
    effective_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_merchant_active_currency UNIQUE (merchant_id, target_currency, is_active)
);

ALTER TABLE public.currency_exchange_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_currency_rates" ON public.currency_exchange_rates
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_currency_exchange_rates_merchant ON public.currency_exchange_rates (merchant_id, is_active);


COMMIT;
