-- =========================================================================
-- Migration 008: Employee Face Embedding and EmployeeShift Sync
-- Created: 2026-06-12
-- Description: Adds face_embedding column for storing facial recognition
--              templates as base64-encoded binary data. Also adds sync
--              metadata columns to employee_shifts for bidirectional sync.
-- Status: PENDING
-- =========================================================================

-- -------------------------------------------------------------------------
-- 8.1 employees — Face embedding storage for biometric verification
-- -------------------------------------------------------------------------
ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS face_embedding TEXT,
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;

-- -------------------------------------------------------------------------
-- 8.2 employee_shifts — Sync metadata for cross-device shift scheduling
-- -------------------------------------------------------------------------
ALTER TABLE public.employee_shifts
    ADD COLUMN IF NOT EXISTS merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Back-fill merchant_id for existing employee_shifts via employees -> merchants
UPDATE public.employee_shifts es
SET merchant_id = e.merchant_id
FROM public.employees e
WHERE es.employee_id = e.id AND es.merchant_id IS NULL;

-- Make merchant_id NOT NULL after back-fill
ALTER TABLE public.employee_shifts
    ALTER COLUMN merchant_id SET NOT NULL;

-- -------------------------------------------------------------------------
-- 8.3 RLS for employee_shifts
-- -------------------------------------------------------------------------
ALTER TABLE public.employee_shifts ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "merchant_isolation_employee_shifts" ON public.employee_shifts
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- -------------------------------------------------------------------------
-- 8.4 Indexes
-- -------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_employee_shifts_merchant ON public.employee_shifts (merchant_id);
CREATE INDEX IF NOT EXISTS idx_employee_shifts_employee ON public.employee_shifts (employee_id);
CREATE INDEX IF NOT EXISTS idx_employees_face ON public.employees (face_embedding) WHERE face_embedding IS NOT NULL;
