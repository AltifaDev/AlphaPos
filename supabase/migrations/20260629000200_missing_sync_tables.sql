-- =========================================================================
-- Migration 035: Create Missing Sync Tables
-- Date: 2026-06-29
-- Description:
--   Creates tables for `expenses` and `table_layout_presets` which exist in SwiftData
--   but are absent from Supabase schema.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 35.1 table_layout_presets
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.table_layout_presets (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE NOT NULL,
    floor INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    bg_image_filename VARCHAR(255),
    bg_image_scale DECIMAL(10,6) NOT NULL DEFAULT 1.0,
    bg_image_offset_x DECIMAL(10,2) NOT NULL DEFAULT 0.0,
    bg_image_offset_y DECIMAL(10,2) NOT NULL DEFAULT 0.0,
    table_layout_json TEXT NOT NULL,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.table_layout_presets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_table_layout_presets" ON public.table_layout_presets
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_table_layout_presets_merchant ON public.table_layout_presets (merchant_id);
CREATE INDEX IF NOT EXISTS idx_table_layout_presets_branch ON public.table_layout_presets (branch_id);

-- -------------------------------------------------------------------------
-- 35.2 expenses
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.expenses (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    invoice_no VARCHAR(100),
    title VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    quantity DECIMAL(12,3) NOT NULL DEFAULT 1.0,
    unit VARCHAR(50),
    unit_price DECIMAL(12,2) NOT NULL DEFAULT 0.0,
    amount DECIMAL(12,2) NOT NULL DEFAULT 0.0,
    vat_rate DECIMAL(5,2) NOT NULL DEFAULT 0.0,
    vat_amount DECIMAL(12,2) NOT NULL DEFAULT 0.0,
    payment_method VARCHAR(100) NOT NULL DEFAULT 'Cash',
    status VARCHAR(50) NOT NULL DEFAULT 'Paid',
    is_capex BOOLEAN NOT NULL DEFAULT FALSE,
    date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    notes TEXT,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_expenses" ON public.expenses
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_expenses_merchant ON public.expenses (merchant_id);
CREATE INDEX IF NOT EXISTS idx_expenses_branch ON public.expenses (branch_id);
