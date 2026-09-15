BEGIN;

ALTER TABLE public.merchants
    ADD COLUMN IF NOT EXISTS printer_preferences JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMIT;
