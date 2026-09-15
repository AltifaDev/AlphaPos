-- Ensure menu_items.is_available exists for POS ↔ web sold-out sync
ALTER TABLE public.menu_items
    ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT TRUE;

UPDATE public.menu_items
SET is_available = TRUE
WHERE is_available IS NULL;
