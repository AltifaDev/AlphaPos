-- =========================================================================
-- Migration 019: Inventory + Promotion Integrity
-- Created: 2026-06-16
-- Description:
--   Closes the remaining promotion/inventory data contract gaps:
--   - Full promotion rule fields and foreign-key validation.
--   - Bundle promotion component table.
--   - Structured inventory transaction columns and idempotency guard.
--   - Branch-aware, idempotent server-side stock deduction trigger.
--
-- Safe to re-run. Constraints that may meet legacy data are added NOT VALID.
-- =========================================================================

BEGIN;

-- -------------------------------------------------------------------------
-- 19.1 Promotion rule completeness
-- -------------------------------------------------------------------------
ALTER TABLE public.promotions
    ADD COLUMN IF NOT EXISTS reward_menu_item_id TEXT,
    ADD COLUMN IF NOT EXISTS max_redemptions INTEGER,
    ADD COLUMN IF NOT EXISTS current_redemptions INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS per_customer_limit INTEGER;

ALTER TABLE public.promotions
    DROP CONSTRAINT IF EXISTS promotions_discount_type_check;

ALTER TABLE public.promotions
    ADD CONSTRAINT promotions_discount_type_check
    CHECK (discount_type IN ('none', 'percentage', 'fixed', 'bundle_price', 'buy_x_get_y', 'buy_x_pay_y')) NOT VALID;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_applies_to_menu_item_fk') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_applies_to_menu_item_fk
            FOREIGN KEY (applies_to_menu_item_id)
            REFERENCES public.menu_items(id)
            ON DELETE SET NULL
            NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_reward_menu_item_fk') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_reward_menu_item_fk
            FOREIGN KEY (reward_menu_item_id)
            REFERENCES public.menu_items(id)
            ON DELETE SET NULL
            NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_redemption_limits_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_redemption_limits_check
            CHECK (
                current_redemptions >= 0
                AND (max_redemptions IS NULL OR max_redemptions >= 0)
                AND (per_customer_limit IS NULL OR per_customer_limit >= 1)
                AND (max_redemptions IS NULL OR current_redemptions <= max_redemptions)
            ) NOT VALID;
    END IF;

    ALTER TABLE public.promotions
        DROP CONSTRAINT IF EXISTS promotions_product_rule_check;

    ALTER TABLE public.promotions
        ADD CONSTRAINT promotions_product_rule_check
        CHECK (
            discount_type NOT IN ('bundle_price', 'buy_x_get_y', 'buy_x_pay_y')
            OR (
                applies_to_menu_item_id IS NOT NULL
                AND length(trim(applies_to_menu_item_id)) > 0
                AND required_quantity >= 1
                AND (
                    (discount_type = 'bundle_price' AND discount_value > 0)
                    OR (discount_type = 'buy_x_get_y' AND reward_quantity >= 1)
                    OR (discount_type = 'buy_x_pay_y' AND reward_quantity >= 1 AND reward_quantity < required_quantity)
                )
            )
        ) NOT VALID;
END $$;

CREATE INDEX IF NOT EXISTS idx_promotions_effective
    ON public.promotions (merchant_id, is_active, is_deleted, starts_at, ends_at, current_redemptions);

CREATE INDEX IF NOT EXISTS idx_promotions_reward_item
    ON public.promotions (merchant_id, reward_menu_item_id)
    WHERE reward_menu_item_id IS NOT NULL;

-- -------------------------------------------------------------------------
-- 19.2 Bundle promotion components
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promotion_bundle_items (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    promotion_id UUID REFERENCES public.promotions(id) ON DELETE CASCADE NOT NULL,
    menu_item_id TEXT REFERENCES public.menu_items(id) ON DELETE CASCADE NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1),
    display_order INTEGER NOT NULL DEFAULT 0,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.promotion_bundle_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_promotion_bundle_items" ON public.promotion_bundle_items;
CREATE POLICY "merchant_isolation_promotion_bundle_items" ON public.promotion_bundle_items
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE UNIQUE INDEX IF NOT EXISTS idx_promotion_bundle_items_unique_component
    ON public.promotion_bundle_items (merchant_id, promotion_id, menu_item_id)
    WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_promotion_bundle_items_promotion
    ON public.promotion_bundle_items (promotion_id, display_order)
    WHERE is_deleted = FALSE;

-- -------------------------------------------------------------------------
-- 19.3 Order discount FK to promotion for redemption audit integrity
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.order_discounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    promotion_id UUID,
    discount_type VARCHAR(30) NOT NULL,
    discount_value DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) NOT NULL,
    reason TEXT,
    applied_by_employee_id UUID,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.order_discounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_order_discounts" ON public.order_discounts;
CREATE POLICY "merchant_isolation_order_discounts" ON public.order_discounts
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

DO $$
BEGIN
    IF to_regclass('public.order_discounts') IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'order_discounts_promotion_fk') THEN
            ALTER TABLE public.order_discounts
                ADD CONSTRAINT order_discounts_promotion_fk
                FOREIGN KEY (promotion_id)
                REFERENCES public.promotions(id)
                ON DELETE SET NULL
                NOT VALID;
        END IF;

        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_order_discounts_promotion_customer
                 ON public.order_discounts (merchant_id, promotion_id, order_id)
                 WHERE is_deleted = FALSE';
    END IF;
END $$;

-- -------------------------------------------------------------------------
-- 19.4 Structured inventory transaction contract + idempotency
-- -------------------------------------------------------------------------
ALTER TABLE public.order_items
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;

ALTER TABLE public.inventory_transactions
    ADD COLUMN IF NOT EXISTS item_name VARCHAR(200) NOT NULL DEFAULT 'Unknown',
    ADD COLUMN IF NOT EXISTS type VARCHAR(50) NOT NULL DEFAULT 'sell',
    ADD COLUMN IF NOT EXISTS item_id UUID REFERENCES public.inventory_items(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS transaction_type VARCHAR(50),
    ADD COLUMN IF NOT EXISTS cost_price DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS reference_id UUID,
    ADD COLUMN IF NOT EXISTS notes TEXT,
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'inventory_transactions' AND column_name = 'type') THEN
        EXECUTE 'UPDATE public.inventory_transactions
                 SET transaction_type = COALESCE(transaction_type, type),
                     updated_at = COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
                 WHERE transaction_type IS NULL';
    ELSE
        UPDATE public.inventory_transactions
        SET transaction_type = COALESCE(transaction_type, 'sell'),
            updated_at = COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
        WHERE transaction_type IS NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'inventory_transactions_type_check') THEN
        ALTER TABLE public.inventory_transactions
            ADD CONSTRAINT inventory_transactions_type_check
            CHECK (
                COALESCE(transaction_type, type) IN (
                    'receive', 'waste', 'adjust', 'sell', 'return_to_supplier',
                    'refund_return', 'transfer_out', 'transfer_in'
                )
            ) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'inventory_transactions_reference_unique') THEN
        ALTER TABLE public.inventory_transactions
            ADD CONSTRAINT inventory_transactions_reference_unique
            UNIQUE (merchant_id, transaction_type, reference_id, item_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item_branch_time
    ON public.inventory_transactions (merchant_id, item_id, branch_id, updated_at DESC)
    WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_reference
    ON public.inventory_transactions (merchant_id, reference_id)
    WHERE reference_id IS NOT NULL AND is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_inventory_items_high_volume_lookup
    ON public.inventory_items (merchant_id, branch_id, is_deleted, name, sku, barcode);

CREATE INDEX IF NOT EXISTS idx_recipes_menu_item_active
    ON public.recipes (menu_item_id, inventory_item_id)
    WHERE is_deleted = FALSE;

-- -------------------------------------------------------------------------
-- 19.5 Branch-aware, idempotent stock deduction trigger
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deduct_stock_on_order_item_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    r_recipe RECORD;
    r_modifier RECORD;
    v_branch_id UUID;
    v_transaction_exists BOOLEAN;
BEGIN
    IF NOT (
        NEW.status IN ('cooking', 'served')
        AND (TG_OP = 'INSERT' OR OLD.status IS NULL OR OLD.status = 'pending')
    ) THEN
        RETURN NEW;
    END IF;

    v_branch_id := NEW.branch_id;
    IF v_branch_id IS NULL THEN
        SELECT o.branch_id
        INTO v_branch_id
        FROM public.orders o
        WHERE o.id = NEW.order_id;
    END IF;

    -- 1. Deduct base menu item recipe ingredients.
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
        SELECT EXISTS (
            SELECT 1
            FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = NEW.id
              AND it.item_id = r_recipe.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        IF NOT v_transaction_exists THEN
            UPDATE public.inventory_items
            SET current_quantity = current_quantity - (r_recipe.quantity_required * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE
            WHERE id = r_recipe.inventory_item_id;

            INSERT INTO public.inventory_transactions (
                id, merchant_id, item_id, item_name, transaction_type, type,
                quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
            )
            SELECT
                uuid_generate_v4(), NEW.merchant_id, r_recipe.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                'sell', 'sell', -(r_recipe.quantity_required * NEW.quantity),
                NEW.id, 'Auto-deducted base recipe for Order Item ID: ' || NEW.id,
                v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM public.inventory_items ii
            WHERE ii.id = r_recipe.inventory_item_id;
        END IF;
    END LOOP;

    -- 2. Deduct selected modifier ingredients.
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
        SELECT EXISTS (
            SELECT 1
            FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = r_modifier.oim_id
              AND it.item_id = r_modifier.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        IF NOT v_transaction_exists THEN
            UPDATE public.inventory_items
            SET current_quantity = current_quantity - (r_modifier.quantity_required * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE
            WHERE id = r_modifier.inventory_item_id;

            INSERT INTO public.inventory_transactions (
                id, merchant_id, item_id, item_name, transaction_type, type,
                quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
            )
            SELECT
                uuid_generate_v4(), NEW.merchant_id, r_modifier.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                'sell', 'sell', -(r_modifier.quantity_required * NEW.quantity),
                r_modifier.oim_id, 'Auto-deducted modifier (' || r_modifier.modifier_name || ')',
                v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM public.inventory_items ii
            WHERE ii.id = r_modifier.inventory_item_id;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deduct_stock_on_order_item ON public.order_items;
CREATE TRIGGER trg_deduct_stock_on_order_item
AFTER INSERT OR UPDATE OF status ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.deduct_stock_on_order_item_event();

COMMIT;
