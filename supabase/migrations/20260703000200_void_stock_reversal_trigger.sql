-- =========================================================================
-- Migration: Void/Cancel Order Item Stock Reversal Trigger
-- Created: 2026-07-03
-- Description: Creates a trigger that restores raw material stock levels
--              when an order item is cancelled or voided after being sent
--              to the kitchen (transitioning from 'cooking'/'served' to 'cancelled').
-- =========================================================================

BEGIN;

-- 1. Create or replace the function to revert stock
CREATE OR REPLACE FUNCTION public.revert_stock_on_void_or_cancel_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    r_recipe RECORD;
    r_modifier RECORD;
    v_branch_id UUID;
    v_transaction_exists BOOLEAN;
    v_void_logged BOOLEAN;
BEGIN
    -- Only trigger when status is updated to 'cancelled' from 'cooking' or 'served'
    -- (meaning the stock was already deducted)
    IF NOT (
        NEW.status = 'cancelled'
        AND (OLD.status = 'cooking' OR OLD.status = 'served')
    ) THEN
        RETURN NEW;
    END IF;

    v_branch_id := NEW.branch_id;
    IF v_branch_id IS NULL THEN
        SELECT o.branch_id INTO v_branch_id FROM public.orders o WHERE o.id = NEW.order_id;
    END IF;

    -- 1. Revert base menu item recipe ingredients
    FOR r_recipe IN
        SELECT r.inventory_item_id, r.quantity_required
        FROM public.recipes r
        JOIN public.inventory_items ii ON ii.id = r.inventory_item_id
        WHERE r.menu_item_id::text = NEW.item_id
          AND COALESCE(r.is_deleted, FALSE) = FALSE
          AND ii.merchant_id = NEW.merchant_id
          AND COALESCE(ii.is_deleted, FALSE) = FALSE
          AND (v_branch_id IS NULL OR ii.branch_id = v_branch_id)
    LOOP
        -- Check if a deduction transaction exists for this item
        SELECT EXISTS (
            SELECT 1 FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = NEW.id
              AND it.item_id = r_recipe.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        -- Only revert if it was deducted and not yet voided/reverted
        IF v_transaction_exists THEN
            SELECT EXISTS (
                SELECT 1 FROM public.inventory_transactions it
                WHERE it.merchant_id = NEW.merchant_id
                  AND it.transaction_type = 'void'
                  AND it.reference_id = NEW.id
                  AND it.item_id = r_recipe.inventory_item_id
                  AND COALESCE(it.is_deleted, FALSE) = FALSE
            ) INTO v_void_logged;

            IF NOT v_void_logged THEN
                -- Restore stock quantity
                UPDATE public.inventory_items
                SET current_quantity = current_quantity + (r_recipe.quantity_required * NEW.quantity),
                    updated_at = CURRENT_TIMESTAMP,
                    is_synced = FALSE
                WHERE id = r_recipe.inventory_item_id;

                -- Log void transaction for Audit Trail
                INSERT INTO public.inventory_transactions (
                    id, merchant_id, item_id, item_name, transaction_type, type,
                    quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
                )
                SELECT
                    uuid_generate_v4(), NEW.merchant_id, r_recipe.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                    'void', 'void', (r_recipe.quantity_required * NEW.quantity),
                    NEW.id, 'Stock restored due to Void/Cancel of Order Item ID: ' || NEW.id,
                    v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM public.inventory_items ii
                WHERE ii.id = r_recipe.inventory_item_id;
            END IF;
        END IF;
    END LOOP;

    -- 2. Revert selected modifier ingredients
    FOR r_modifier IN
        SELECT m.inventory_item_id, m.quantity_required, m.name AS modifier_name, oim.id AS oim_id
        FROM public.order_item_modifiers oim
        JOIN public.modifiers m ON oim.modifier_id = m.id
        JOIN public.inventory_items ii ON ii.id = m.inventory_item_id
        WHERE oim.order_item_id = NEW.id
          AND m.inventory_item_id IS NOT NULL
          AND COALESCE(oim.is_deleted, FALSE) = FALSE
          AND COALESCE(m.is_deleted, FALSE) = FALSE
          AND ii.merchant_id = NEW.merchant_id
          AND COALESCE(ii.is_deleted, FALSE) = FALSE
          AND (v_branch_id IS NULL OR ii.branch_id = v_branch_id)
    LOOP
        -- Check if modifier deduction exists
        SELECT EXISTS (
            SELECT 1 FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = r_modifier.oim_id
              AND it.item_id = r_modifier.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        IF v_transaction_exists THEN
            SELECT EXISTS (
                SELECT 1 FROM public.inventory_transactions it
                WHERE it.merchant_id = NEW.merchant_id
                  AND it.transaction_type = 'void'
                  AND it.reference_id = r_modifier.oim_id
                  AND it.item_id = r_modifier.inventory_item_id
                  AND COALESCE(it.is_deleted, FALSE) = FALSE
            ) INTO v_void_logged;

            IF NOT v_void_logged THEN
                -- Restore stock quantity
                UPDATE public.inventory_items
                SET current_quantity = current_quantity + (r_modifier.quantity_required * NEW.quantity),
                    updated_at = CURRENT_TIMESTAMP,
                    is_synced = FALSE
                WHERE id = r_modifier.inventory_item_id;

                -- Log void transaction for Audit Trail
                INSERT INTO public.inventory_transactions (
                    id, merchant_id, item_id, item_name, transaction_type, type,
                    quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
                )
                SELECT
                    uuid_generate_v4(), NEW.merchant_id, r_modifier.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                    'void', 'void', (r_modifier.quantity_required * NEW.quantity),
                    r_modifier.oim_id, 'Stock restored due to Void/Cancel of modifier (' || r_modifier.modifier_name || ')',
                    v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM public.inventory_items ii
                WHERE ii.id = r_modifier.inventory_item_id;
            END IF;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 2. Bind the trigger to order_items
DROP TRIGGER IF EXISTS trg_revert_stock_on_void ON public.order_items;
CREATE TRIGGER trg_revert_stock_on_void
AFTER UPDATE OF status ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.revert_stock_on_void_or_cancel_event();

COMMIT;
