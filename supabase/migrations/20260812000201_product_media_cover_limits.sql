-- Store cover videos are larger than menu thumbnails but remain bounded.
UPDATE storage.buckets
SET file_size_limit = 52428800,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'video/mp4']
WHERE id = 'product-media';
