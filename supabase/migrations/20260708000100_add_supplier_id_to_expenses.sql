-- =========================================================================
-- Migration: Add supplier_id to public.expenses
-- Date: 2026-07-08
-- Description:
--   Adds missing `supplier_id` column and its foreign key constraint referencing
--   `public.suppliers(id)` to support expense-to-supplier mapping.
-- =========================================================================

ALTER TABLE public.expenses 
    ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL;
