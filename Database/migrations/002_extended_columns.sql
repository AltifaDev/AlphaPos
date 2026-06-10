-- =========================================================================
-- Migration 002: Extended Columns for iPad POS SwiftData Sync
-- Created: 2026-06-09
-- Description: Adds columns required to sync SwiftData models from the
--              iPad POS app. All ALTER TABLE statements use ADD COLUMN IF NOT EXISTS
--              so they are safe to re-run (idempotent).
-- Status: APPLIED to Supabase (sdmtkixrqkmwcpwoisrg)
-- =========================================================================

-- -------------------------------------------------------------------------
-- 2.1 employees — Extended profile fields for staff management
-- -------------------------------------------------------------------------
ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS bank_account_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS bank_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS joined_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS face_registered_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS email VARCHAR(255),
    ADD COLUMN IF NOT EXISTS date_of_birth DATE,
    ADD COLUMN IF NOT EXISTS address TEXT,
    ADD COLUMN IF NOT EXISTS emergency_contact_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS emergency_contact_phone VARCHAR(50),
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- -------------------------------------------------------------------------
-- 2.2 inventory_items — Warehouse management fields
-- -------------------------------------------------------------------------
ALTER TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS category VARCHAR(100),
    ADD COLUMN IF NOT EXISTS storage_location VARCHAR(200),
    ADD COLUMN IF NOT EXISTS barcode VARCHAR(100);

-- -------------------------------------------------------------------------
-- 2.3 inventory_transactions — Full structured fields (was text-only)
-- -------------------------------------------------------------------------
ALTER TABLE public.inventory_transactions
    ADD COLUMN IF NOT EXISTS item_id UUID REFERENCES public.inventory_items(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS transaction_type VARCHAR(50),
    ADD COLUMN IF NOT EXISTS cost_price DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS reference_id UUID,
    ADD COLUMN IF NOT EXISTS notes TEXT,
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- -------------------------------------------------------------------------
-- 2.4 orders — POS-specific financial fields
-- -------------------------------------------------------------------------
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS order_type VARCHAR(50) DEFAULT 'dine_in',
    ADD COLUMN IF NOT EXISTS subtotal DECIMAL(10,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS tax DECIMAL(10,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS service_charge DECIMAL(10,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS discount DECIMAL(10,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS table_session_id UUID REFERENCES public.table_sessions(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS guest_count INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS cashier_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS queue_number VARCHAR(20),
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE;

-- -------------------------------------------------------------------------
-- 2.5 order_items — Line item details
-- -------------------------------------------------------------------------
ALTER TABLE public.order_items
    ADD COLUMN IF NOT EXISTS unit_price DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS subtotal DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS notes TEXT,
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- -------------------------------------------------------------------------
-- 2.6 payments — Transaction tracking fields
-- -------------------------------------------------------------------------
ALTER TABLE public.payments
    ADD COLUMN IF NOT EXISTS transaction_reference VARCHAR(255),
    ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- -------------------------------------------------------------------------
-- 2.7 timecards — Face recognition and shift linkage fields
-- -------------------------------------------------------------------------
ALTER TABLE public.timecards
    ADD COLUMN IF NOT EXISTS shift_id UUID REFERENCES public.employee_shifts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_by_user_id UUID,
    ADD COLUMN IF NOT EXISTS clock_in_selfie_url TEXT,
    ADD COLUMN IF NOT EXISTS clock_out_selfie_url TEXT,
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
