-- Adds common quantity reward promotion rules:
-- buy_x_get_y (for example Buy 1 Get 1) and buy_x_pay_y (for example Buy 3 Pay 2).

ALTER TABLE public.promotions
    ADD COLUMN IF NOT EXISTS reward_quantity INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.promotions
    DROP CONSTRAINT IF EXISTS promotions_discount_type_check;

ALTER TABLE public.promotions
    ADD CONSTRAINT promotions_discount_type_check
    CHECK (discount_type IN ('none', 'percentage', 'fixed', 'bundle_price', 'buy_x_get_y', 'buy_x_pay_y')) NOT VALID;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_reward_quantity_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_reward_quantity_check
            CHECK (reward_quantity >= 0) NOT VALID;
    END IF;

    ALTER TABLE public.promotions
        DROP CONSTRAINT IF EXISTS promotions_bundle_product_check;

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

CREATE INDEX IF NOT EXISTS idx_promotions_quantity_rewards
    ON public.promotions (merchant_id, discount_type, applies_to_menu_item_id, is_active, is_deleted);
