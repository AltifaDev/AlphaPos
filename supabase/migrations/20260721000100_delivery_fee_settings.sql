ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS delivery_fee_settings JSONB NOT NULL DEFAULT '{}'::jsonb;
