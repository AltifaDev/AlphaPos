-- Product-media objects are namespaced as <merchant_id>/... .
-- Auth stores merchant_id in app_metadata, so use the canonical tenant helper
-- instead of reading a non-existent top-level JWT claim.

DROP POLICY IF EXISTS "product_media_select" ON storage.objects;
DROP POLICY IF EXISTS "product_media_insert" ON storage.objects;
DROP POLICY IF EXISTS "product_media_update" ON storage.objects;
DROP POLICY IF EXISTS "product_media_delete" ON storage.objects;

CREATE POLICY "product_media_select"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = public.get_active_merchant_id()::text
);

CREATE POLICY "product_media_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = public.get_active_merchant_id()::text
);

CREATE POLICY "product_media_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = public.get_active_merchant_id()::text
)
WITH CHECK (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = public.get_active_merchant_id()::text
);

CREATE POLICY "product_media_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'product-media'
    AND (storage.foldername(name))[1] = public.get_active_merchant_id()::text
);
