-- Migration: 024_menu_items_localization.sql
-- Add localization support for product (menu_item) names and descriptions in PostgreSQL

ALTER TABLE menu_items ADD COLUMN IF NOT EXISTS name_translations JSONB DEFAULT '{}'::jsonb;
ALTER TABLE menu_items ADD COLUMN IF NOT EXISTS description_translations JSONB DEFAULT '{}'::jsonb;
