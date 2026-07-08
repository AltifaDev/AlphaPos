-- 030_expenses.sql
-- AlphaPos — Migration for Expenses Tracking (PostgreSQL Central DB)

-- 1. Create public.expenses table with detailed columns
CREATE TABLE IF NOT EXISTS public.expenses (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    invoice_no VARCHAR(100),
    title VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL, -- Raw Materials, Equipment, Consumables, Maintenance, Other
    quantity NUMERIC NOT NULL DEFAULT 1.00,
    unit VARCHAR(50),
    unit_price NUMERIC NOT NULL DEFAULT 0.00,
    amount NUMERIC NOT NULL DEFAULT 0.00,
    vat_rate NUMERIC NOT NULL DEFAULT 0.00,
    vat_amount NUMERIC NOT NULL DEFAULT 0.00,
    payment_method VARCHAR(50) NOT NULL DEFAULT 'Cash', -- Cash, Credit Card, Bank Transfer, Accounts Payable
    status VARCHAR(50) NOT NULL DEFAULT 'Paid', -- Paid, Unpaid
    is_capex BOOLEAN NOT NULL DEFAULT FALSE,
    date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    notes TEXT,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Enable Row Level Security (RLS)
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

-- 3. Create Tenant Isolation RLS Policy
CREATE POLICY "merchant_isolation_expenses" ON public.expenses
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- 4. Create Indexes for performance
CREATE INDEX IF NOT EXISTS idx_expenses_merchant ON public.expenses (merchant_id);
CREATE INDEX IF NOT EXISTS idx_expenses_branch ON public.expenses (branch_id);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON public.expenses (merchant_id, category);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON public.expenses (merchant_id, date);
