-- Product-linked promotion rules for quantity bundles such as "Buy 3 beers for 299".

ALTER TABLE public.promotions
    ADD COLUMN IF NOT EXISTS applies_to_menu_item_id TEXT,
    ADD COLUMN IF NOT EXISTS required_quantity INTEGER NOT NULL DEFAULT 1;

ALTER TABLE public.promotions
    DROP CONSTRAINT IF EXISTS promotions_discount_type_check;

ALTER TABLE public.promotions
    ADD CONSTRAINT promotions_discount_type_check
    CHECK (discount_type IN ('none', 'percentage', 'fixed', 'bundle_price')) NOT VALID;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_required_quantity_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_required_quantity_check
            CHECK (required_quantity >= 1) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_bundle_product_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_bundle_product_check
            CHECK (
                discount_type <> 'bundle_price'
                OR (
                    applies_to_menu_item_id IS NOT NULL
                    AND length(trim(applies_to_menu_item_id)) > 0
                    AND discount_value > 0
                )
            ) NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_promotions_product_rule
    ON public.promotions (merchant_id, applies_to_menu_item_id, is_active, is_deleted);
