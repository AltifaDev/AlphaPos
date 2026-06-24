-- =========================================================================
-- Migration 020: Validate Inventory + Promotion Integrity
-- Created: 2026-06-16
-- Description:
--   Production repair/validation migration for environments where 019 was
--   applied before the enterprise order_discounts table existed.
--
-- Safe to re-run. It creates the missing order_discounts contract, ensures the
-- promotion FK exists, then validates the integrity constraints required to
-- close the inventory/promotion database contract.
-- =========================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

ALTER TABLE public.promotions
    ADD COLUMN IF NOT EXISTS reward_menu_item_id TEXT,
    ADD COLUMN IF NOT EXISTS max_redemptions INTEGER,
    ADD COLUMN IF NOT EXISTS current_redemptions INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS per_customer_limit INTEGER;

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
END $$;

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
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'order_discounts_promotion_fk') THEN
        ALTER TABLE public.order_discounts
            ADD CONSTRAINT order_discounts_promotion_fk
            FOREIGN KEY (promotion_id)
            REFERENCES public.promotions(id)
            ON DELETE SET NULL
            NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_order_discounts_merchant
    ON public.order_discounts (merchant_id);

CREATE INDEX IF NOT EXISTS idx_order_discounts_order
    ON public.order_discounts (order_id);

CREATE INDEX IF NOT EXISTS idx_order_discounts_promotion_customer
    ON public.order_discounts (merchant_id, promotion_id, order_id)
    WHERE is_deleted = FALSE;

ALTER TABLE public.promotions VALIDATE CONSTRAINT promotions_applies_to_menu_item_fk;
ALTER TABLE public.promotions VALIDATE CONSTRAINT promotions_reward_menu_item_fk;
ALTER TABLE public.promotions VALIDATE CONSTRAINT promotions_product_rule_check;
ALTER TABLE public.promotions VALIDATE CONSTRAINT promotions_redemption_limits_check;
ALTER TABLE public.order_discounts VALIDATE CONSTRAINT order_discounts_promotion_fk;

COMMIT;
