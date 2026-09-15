BEGIN;

ALTER TABLE public.merchants
    ADD COLUMN IF NOT EXISTS printer_preferences JSONB NOT NULL DEFAULT '{}'::jsonb;

-- PostgREST can retain the pre-migration schema and return PGRST204 even after
-- the column exists. Notify it as part of the migration so every environment
-- refreshes the API schema immediately.
NOTIFY pgrst, 'reload schema';

COMMIT;
