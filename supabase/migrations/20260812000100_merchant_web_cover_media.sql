-- Optional customer-ordering cover media. A merchant can use a still image or
-- a muted looping video independently from time-limited promotions.
ALTER TABLE public.merchants
    ADD COLUMN IF NOT EXISTS web_cover_url TEXT,
    ADD COLUMN IF NOT EXISTS web_cover_media_type TEXT NOT NULL DEFAULT 'image';

ALTER TABLE public.merchants
    DROP CONSTRAINT IF EXISTS merchants_web_cover_media_type_check;

ALTER TABLE public.merchants
    ADD CONSTRAINT merchants_web_cover_media_type_check
    CHECK (web_cover_media_type IN ('image', 'video'));

COMMENT ON COLUMN public.merchants.web_cover_url IS
    'Public HTTPS URL or data URI used as the customer-ordering hero when no promotion is active.';
COMMENT ON COLUMN public.merchants.web_cover_media_type IS
    'Customer-ordering hero media type: image or video.';
