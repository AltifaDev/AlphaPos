-- =========================================================================
-- Migration: Yield Percentage, Reason Codes & Index Optimizations
-- Created: 2026-07-03
-- Description:
--   1. Adds yield_percentage field to public.recipes to handle waste loss.
--   2. Adds reason_code field to public.inventory_transactions for stock audits.
--   3. Creates an expression index on recipes( (menu_item_id::text) ) to optimize trigger queries.
-- =========================================================================

BEGIN;

-- 1. Add yield_percentage column to recipes table
ALTER TABLE public.recipes
    ADD COLUMN IF NOT EXISTS yield_percentage NUMERIC DEFAULT 100.00
    CONSTRAINT check_yield_range CHECK (yield_percentage > 0 AND yield_percentage <= 100.00);

-- 2. Add reason_code column to inventory_transactions table
ALTER TABLE public.inventory_transactions
    ADD COLUMN IF NOT EXISTS reason_code VARCHAR(50);

-- 3. Create index for reason_code
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_reason ON public.inventory_transactions (reason_code);

-- 4. Create Expression Index to optimize trigger query performance (UUID to TEXT cast)
CREATE INDEX IF NOT EXISTS idx_recipes_menu_item_text
    ON public.recipes ((menu_item_id::text));

COMMIT;
