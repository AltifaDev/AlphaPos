-- Store product media in Supabase Storage and keep only public URLs on menu_items.

ALTER TABLE public.menu_items
    ADD COLUMN IF NOT EXISTS image_url_2 TEXT,
    ADD COLUMN IF NOT EXISTS image_url_3 TEXT,
    ADD COLUMN IF NOT EXISTS video_url TEXT;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'product-media',
    'product-media',
    true,
    15728640,
    ARRAY['image/jpeg', 'video/mp4']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "product_media_insert" ON storage.objects;
DROP POLICY IF EXISTS "product_media_update" ON storage.objects;
DROP POLICY IF EXISTS "product_media_delete" ON storage.objects;

CREATE POLICY "product_media_insert"
ON storage.objects FOR INSERT TO public
WITH CHECK (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
);

CREATE POLICY "product_media_update"
ON storage.objects FOR UPDATE TO public
USING (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
)
WITH CHECK (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
);

CREATE POLICY "product_media_delete"
ON storage.objects FOR DELETE TO public
USING (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
);
