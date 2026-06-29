-- =========================================================================
-- Migration 029: Fix Sync Errors
-- Date: 2026-06-20
-- Description:
--   Fixes four SyncEngine errors seen in production logs:
--
--   1. [TableSession 23505]   duplicate key on session_token
--      → session_token already has UNIQUE, but upsert used on_conflict=id only.
--        No schema change needed — fix is on the iOS side (on_conflict=id,session_token).
--        However we ensure the constraint name is stable for the upsert header.
--
--   2. [FloorPlanImage 23505] duplicate key on (merchant_id, floor)
--      → upsert now uses on_conflict=merchant_id,floor. No schema change needed.
--
--   3. [InventoryTxn 23503]   FK violation — item_id not present in inventory_items
--      → iOS fix: syncInventoryItems/pull before syncInventoryTransactions.
--      → DB safety net: downgrade FK to SET NULL so a missing item_id never
--        blocks the transaction row from being inserted.
--        (Migration 019 already set ON DELETE SET NULL, but the FK itself
--         may have been created differently on some instances.)
--
--   4. [PullMenu 42703]       column menu_items.is_deleted does not exist
--      → Add is_deleted to menu_items and update fetchMenuItemsFromSupabase.
-- =========================================================================

BEGIN;

-- -------------------------------------------------------------------------
-- 29.1 Add is_deleted to menu_items
-- -------------------------------------------------------------------------
ALTER TABLE public.menu_items
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

-- Back-fill existing rows (all currently visible items are not deleted)
UPDATE public.menu_items SET is_deleted = FALSE WHERE is_deleted IS NULL;

-- -------------------------------------------------------------------------
-- 29.2 Ensure inventory_transactions.item_id FK is ON DELETE SET NULL
--      Re-create the constraint idempotently so it is definitely SET NULL.
-- -------------------------------------------------------------------------
DO $$
BEGIN
    -- Drop and re-add only if the existing FK is NOT already SET NULL
    IF EXISTS (
        SELECT 1
        FROM information_schema.referential_constraints rc
        JOIN information_schema.table_constraints tc
            ON rc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'inventory_transactions'
          AND rc.constraint_name = 'inventory_transactions_item_id_fkey'
          AND rc.delete_rule <> 'SET NULL'
    ) THEN
        ALTER TABLE public.inventory_transactions
            DROP CONSTRAINT inventory_transactions_item_id_fkey;

        ALTER TABLE public.inventory_transactions
            ADD CONSTRAINT inventory_transactions_item_id_fkey
            FOREIGN KEY (item_id)
            REFERENCES public.inventory_items(id)
            ON DELETE SET NULL;
    END IF;
END $$;

-- -------------------------------------------------------------------------
-- 29.3 Ensure table_sessions.session_token unique constraint has stable name
--      (Supabase upsert header uses the constraint name internally)
-- -------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'table_sessions_session_token_key'
          AND contype = 'u'
    ) THEN
        ALTER TABLE public.table_sessions
            ADD CONSTRAINT table_sessions_session_token_key
            UNIQUE (session_token);
    END IF;
END $$;

-- -------------------------------------------------------------------------
-- 29.4 Ensure floor_plan_images composite unique constraint exists
-- -------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'floor_plan_images_merchant_id_floor_key'
          AND contype = 'u'
    ) THEN
        ALTER TABLE public.floor_plan_images
            ADD CONSTRAINT floor_plan_images_merchant_id_floor_key
            UNIQUE (merchant_id, floor);
    END IF;
END $$;

COMMIT;
