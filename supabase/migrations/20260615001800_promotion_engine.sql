-- Promotion engine: media type, discount rules, and scheduling.
-- Safe to run on an existing Supabase database; it only adds missing columns.

ALTER TABLE public.promotions
    ADD COLUMN IF NOT EXISTS media_type VARCHAR(20) NOT NULL DEFAULT 'image',
    ADD COLUMN IF NOT EXISTS discount_type VARCHAR(30) NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS discount_value DECIMAL(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS minimum_spend DECIMAL(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS starts_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS ends_at TIMESTAMP WITH TIME ZONE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_media_type_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_media_type_check
            CHECK (media_type IN ('image', 'video')) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_discount_type_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_discount_type_check
            CHECK (discount_type IN ('none', 'percentage', 'fixed')) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_discount_value_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_discount_value_check
            CHECK (discount_value >= 0) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_minimum_spend_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_minimum_spend_check
            CHECK (minimum_spend >= 0) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_schedule_check') THEN
        ALTER TABLE public.promotions
            ADD CONSTRAINT promotions_schedule_check
            CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at) NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_promotions_schedule
    ON public.promotions (merchant_id, is_active, is_deleted, starts_at, ends_at);
