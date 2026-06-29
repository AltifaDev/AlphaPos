-- =========================================================================
-- Migration: add_order_items_served_by
-- Date: 2026-06-24
-- Description: Adds a served_by column to store which staff member served the item
-- =========================================================================

-- 1. Add column to live order_items table
ALTER TABLE public.order_items 
    ADD COLUMN IF NOT EXISTS served_by VARCHAR(100) DEFAULT NULL;

-- 2. Add column to archived order_items table
ALTER TABLE public.order_items_archive 
    ADD COLUMN IF NOT EXISTS served_by VARCHAR(100) DEFAULT NULL;
