-- Private, low-resolution attendance evidence retained for at most 30 days.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('timecard-evidence', 'timecard-evidence', false, 153600, ARRAY['image/jpeg'])
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS timecard_evidence_insert_own ON storage.objects;
DROP POLICY IF EXISTS timecard_evidence_select_own ON storage.objects;
DROP POLICY IF EXISTS timecard_evidence_update_own ON storage.objects;
DROP POLICY IF EXISTS timecard_evidence_delete_own ON storage.objects;

CREATE POLICY timecard_evidence_insert_own ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'timecard-evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
);

CREATE POLICY timecard_evidence_select_own ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'timecard-evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
);

CREATE POLICY timecard_evidence_update_own ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'timecard-evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
)
WITH CHECK (
    bucket_id = 'timecard-evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
);

CREATE POLICY timecard_evidence_delete_own ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'timecard-evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'merchant_id')
);

CREATE OR REPLACE FUNCTION public.purge_expired_timecard_evidence()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
    removed integer;
BEGIN
    WITH cleared_in AS (
        UPDATE public.timecards
       SET clock_in_selfie_url = NULL
     WHERE clock_in < now() - interval '30 days'
       AND clock_in_selfie_url IS NOT NULL
        RETURNING 1
    ), cleared_out AS (
        UPDATE public.timecards
           SET clock_out_selfie_url = NULL
         WHERE clock_out < now() - interval '30 days'
           AND clock_out_selfie_url IS NOT NULL
        RETURNING 1
    )
    SELECT (SELECT count(*) FROM cleared_in) + (SELECT count(*) FROM cleared_out)
      INTO removed;

    RETURN removed;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_expired_timecard_evidence() FROM PUBLIC;

-- Storage API protects its object table from direct SQL deletion. Self-hosted
-- deployments schedule scripts/purge-timecard-evidence-vps.sh, which deletes
-- the actual object through Storage API and then calls this metadata cleanup.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule(jobid)
        FROM cron.job
        WHERE jobname = 'purge-timecard-evidence-30d';
    END IF;
END;
$$;
