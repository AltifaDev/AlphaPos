-- =========================================================================
-- Migration 013: Add Table System & Web Ordering configuration to Merchants
-- Created: 2026-06-15
-- Description: Adds configuration columns to merchants table to control
--              access/visibility of tables and self-ordering features.
-- =========================================================================

BEGIN;

ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS is_table_system_enabled BOOLEAN DEFAULT TRUE;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS is_web_ordering_enabled BOOLEAN DEFAULT TRUE;

COMMIT;
