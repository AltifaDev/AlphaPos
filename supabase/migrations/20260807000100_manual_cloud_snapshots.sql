-- Manual, tenant-isolated cloud snapshots for offline AlphaPos installations.
-- Snapshot bytes live in a private Storage bucket. Only immutable metadata is
-- kept in Postgres so backup data can never enter normal business sync tables.

BEGIN;

CREATE TABLE IF NOT EXISTS public.merchant_backup_manifests (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL UNIQUE,
    schema_version INTEGER NOT NULL CHECK (schema_version > 0),
    app_version TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    device_id TEXT NOT NULL,
    record_counts JSONB NOT NULL DEFAULT '{}'::jsonb,
    file_count INTEGER NOT NULL DEFAULT 0 CHECK (file_count >= 0),
    byte_count BIGINT NOT NULL CHECK (byte_count >= 0),
    payload_checksum TEXT NOT NULL CHECK (payload_checksum ~ '^[a-f0-9]{64}$'),
    signature TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'invalid'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_backup_manifests_latest
    ON public.merchant_backup_manifests (merchant_id, created_at DESC)
    WHERE status = 'completed';

ALTER TABLE public.merchant_backup_manifests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_backup_manifests FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.merchant_backup_manifests FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.merchant_backup_manifests TO anon, authenticated;

DROP POLICY IF EXISTS merchant_backup_select_own ON public.merchant_backup_manifests;
CREATE POLICY merchant_backup_select_own
ON public.merchant_backup_manifests FOR SELECT TO public
USING (merchant_id::text = auth.jwt() ->> 'merchant_id');

DROP POLICY IF EXISTS merchant_backup_insert_own ON public.merchant_backup_manifests;
CREATE POLICY merchant_backup_insert_own
ON public.merchant_backup_manifests FOR INSERT TO public
WITH CHECK (
    merchant_id::text = auth.jwt() ->> 'merchant_id'
    AND split_part(storage_path, '/', 1) = merchant_id::text
    AND status = 'completed'
);

DROP POLICY IF EXISTS merchant_backup_delete_own ON public.merchant_backup_manifests;
CREATE POLICY merchant_backup_delete_own
ON public.merchant_backup_manifests FOR DELETE TO public
USING (merchant_id::text = auth.jwt() ->> 'merchant_id');

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'merchant-backups',
    'merchant-backups',
    false,
    536870912,
    ARRAY['application/octet-stream']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS merchant_backups_insert_own ON storage.objects;
CREATE POLICY merchant_backups_insert_own
ON storage.objects FOR INSERT TO public
WITH CHECK (
    bucket_id = 'merchant-backups'
    AND (storage.foldername(name))[1] = auth.jwt() ->> 'merchant_id'
);

DROP POLICY IF EXISTS merchant_backups_select_own ON storage.objects;
CREATE POLICY merchant_backups_select_own
ON storage.objects FOR SELECT TO public
USING (
    bucket_id = 'merchant-backups'
    AND (storage.foldername(name))[1] = auth.jwt() ->> 'merchant_id'
);

DROP POLICY IF EXISTS merchant_backups_delete_own ON storage.objects;
CREATE POLICY merchant_backups_delete_own
ON storage.objects FOR DELETE TO public
USING (
    bucket_id = 'merchant-backups'
    AND (storage.foldername(name))[1] = auth.jwt() ->> 'merchant_id'
);

COMMIT;
