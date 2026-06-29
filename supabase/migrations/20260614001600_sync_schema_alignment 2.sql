-- =========================================================================
-- Migration 014: Align Schema for Sync Enhancements
-- Created: 2026-06-15
-- Description: Adds missing columns required for synchronization of master
--              data (inventory_items, modifiers, menu_item_modifier_groups).
--              All statements use ADD COLUMN IF NOT EXISTS (idempotent).
-- =========================================================================

-- -------------------------------------------------------------------------
-- 14.1 inventory_items — Add supplier_id reference
-- -------------------------------------------------------------------------
ALTER TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- -------------------------------------------------------------------------
-- 14.2 modifiers — Add quantity_required attribute
-- -------------------------------------------------------------------------
ALTER TABLE public.modifiers
    ADD COLUMN IF NOT EXISTS quantity_required DECIMAL(10,2);

-- -------------------------------------------------------------------------
-- 14.3 menu_item_modifier_groups — Add sync metadata
-- -------------------------------------------------------------------------
ALTER TABLE public.menu_item_modifier_groups
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
