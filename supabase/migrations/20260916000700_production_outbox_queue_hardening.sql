-- =========================================================================
-- Migration: 20260916000700_production_outbox_queue_hardening.sql
-- Description: Production-grade Outbox & Asynchronous Job Queue
-- Features:
--   1. Multi-branch isolation (branch_id column & RLS)
--   2. Priority scheduling & station partitioning (job_types filter)
--   3. Worker lease recovery (auto-reclaim jobs stuck in 'processing' > 3 mins)
--   4. Dead-Letter Queue (DLQ) after max attempts with replay RPC
--   5. Jittered exponential backoff for retries
-- =========================================================================

BEGIN;

-- 1. Extend sync_outbox columns
ALTER TABLE public.sync_outbox
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS priority INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS locked_by TEXT,
    ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ;

-- 2. Update status check constraint to include 'dead_letter'
ALTER TABLE public.sync_outbox
    DROP CONSTRAINT IF EXISTS sync_outbox_status_check;

ALTER TABLE public.sync_outbox
    ADD CONSTRAINT sync_outbox_status_check
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'dead_letter'));

-- 3. Composite indexes for high-throughput concurrency and station filtering
CREATE INDEX IF NOT EXISTS idx_sync_outbox_branch_scope
    ON public.sync_outbox (merchant_id, branch_id, status, priority DESC, next_attempt_at)
    WHERE status IN ('pending', 'failed', 'processing');

CREATE INDEX IF NOT EXISTS idx_sync_outbox_job_type
    ON public.sync_outbox (merchant_id, job_type, status)
    WHERE status IN ('pending', 'failed', 'dead_letter');

-- 4. Enforce branch-aware RLS policy on sync_outbox
DROP POLICY IF EXISTS sync_outbox_merchant_isolation ON public.sync_outbox;
DROP POLICY IF EXISTS sync_outbox_tenant_isolation ON public.sync_outbox;

CREATE POLICY sync_outbox_tenant_isolation ON public.sync_outbox
    FOR ALL
    USING (
        merchant_id = public.get_active_merchant_id()
        AND (
            public.get_active_branch_id() IS NULL
            OR branch_id IS NULL
            OR branch_id = public.get_active_branch_id()
        )
    )
    WITH CHECK (
        merchant_id = public.get_active_merchant_id()
        AND (
            public.get_active_branch_id() IS NULL
            OR branch_id IS NULL
            OR branch_id = public.get_active_branch_id()
        )
    );

-- 5. Updated enqueue function with branch_id and priority support
CREATE OR REPLACE FUNCTION public.enqueue_sync_outbox(
    p_idempotency_key TEXT,
    p_job_type TEXT,
    p_payload JSONB DEFAULT '{}'::JSONB,
    p_merchant_id UUID DEFAULT NULL,
    p_branch_id UUID DEFAULT NULL,
    p_priority INTEGER DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := COALESCE(p_merchant_id, public.get_active_merchant_id());
    v_branch_id UUID := COALESCE(p_branch_id, public.get_active_branch_id());
    v_id UUID;
BEGIN
    IF v_merchant_id IS NULL OR NULLIF(trim(p_idempotency_key), '') IS NULL OR NULLIF(trim(p_job_type), '') IS NULL THEN
        RAISE EXCEPTION 'invalid_outbox_enqueue' USING ERRCODE = '22023';
    END IF;

    -- Infer branch_id from payload if omitted
    IF v_branch_id IS NULL AND p_payload ? 'branch_id' THEN
        v_branch_id := NULLIF(p_payload->>'branch_id', '')::UUID;
    END IF;

    INSERT INTO public.sync_outbox (
        merchant_id, branch_id, idempotency_key, job_type, payload, priority, status, next_attempt_at, updated_at
    )
    VALUES (
        v_merchant_id, v_branch_id, trim(p_idempotency_key), trim(p_job_type),
        COALESCE(p_payload, '{}'::JSONB), COALESCE(p_priority, 0), 'pending', now(), now()
    )
    ON CONFLICT (merchant_id, idempotency_key) DO UPDATE
        SET payload = EXCLUDED.payload,
            branch_id = COALESCE(EXCLUDED.branch_id, public.sync_outbox.branch_id),
            priority = GREATEST(public.sync_outbox.priority, EXCLUDED.priority),
            status = CASE WHEN public.sync_outbox.status = 'dead_letter' THEN 'pending' ELSE public.sync_outbox.status END,
            updated_at = now()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- 6. Claim jobs with Lease Timeout Recovery, Station Partitioning & SKIP LOCKED
CREATE OR REPLACE FUNCTION public.claim_sync_outbox(
    p_limit INTEGER DEFAULT 20,
    p_branch_id UUID DEFAULT NULL,
    p_job_types TEXT[] DEFAULT NULL,
    p_worker_id TEXT DEFAULT NULL
)
RETURNS SETOF public.sync_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
    v_branch_id UUID := COALESCE(p_branch_id, public.get_active_branch_id());
    v_worker TEXT := COALESCE(NULLIF(trim(p_worker_id), ''), 'worker-' || substr(gen_random_uuid()::text, 1, 8));
    v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_limit, 20), 100));
BEGIN
    IF v_merchant_id IS NULL THEN
        RETURN;
    END IF;

    -- Lock & reclaim candidates:
    -- 1. 'pending' or 'failed' ready to execute (next_attempt_at <= now() AND attempts < 10)
    -- 2. 'processing' that timed out (lease expired after 3 minutes without completion)
    RETURN QUERY
    WITH picked AS (
        SELECT o.id
          FROM public.sync_outbox o
         WHERE o.merchant_id = v_merchant_id
           AND (v_branch_id IS NULL OR o.branch_id IS NULL OR o.branch_id = v_branch_id)
           AND (p_job_types IS NULL OR o.job_type = ANY(p_job_types))
           AND (
               (o.status IN ('pending', 'failed') AND o.next_attempt_at <= now() AND o.attempts < 10)
               OR
               (o.status = 'processing' AND o.claimed_at < (now() - INTERVAL '3 minutes'))
           )
         ORDER BY o.priority DESC, o.next_attempt_at ASC, o.created_at ASC
         LIMIT v_limit
         FOR UPDATE SKIP LOCKED
    )
    UPDATE public.sync_outbox o
       SET status = 'processing',
           attempts = o.attempts + 1,
           locked_by = v_worker,
           claimed_at = now(),
           updated_at = now()
      FROM picked
     WHERE o.id = picked.id
    RETURNING o.*;
END;
$$;

-- 7. Complete job with Dead-Letter routing and Jittered Exponential Backoff
CREATE OR REPLACE FUNCTION public.complete_sync_outbox(
    p_id UUID,
    p_success BOOLEAN,
    p_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
    v_row public.sync_outbox%ROWTYPE;
    v_jitter_secs INTEGER;
    v_delay_interval INTERVAL;
BEGIN
    SELECT * INTO v_row FROM public.sync_outbox
    WHERE id = p_id AND merchant_id = v_merchant_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF p_success THEN
        UPDATE public.sync_outbox
           SET status = 'completed',
               last_error = NULL,
               locked_by = NULL,
               claimed_at = NULL,
               updated_at = now()
         WHERE id = p_id AND merchant_id = v_merchant_id;
    ELSE
        -- If attempts >= 10, move to dead_letter (DLQ) to prevent infinite loop
        IF v_row.attempts >= 10 THEN
            UPDATE public.sync_outbox
               SET status = 'dead_letter',
                   last_error = LEFT(COALESCE(p_error, 'Exceeded max retry attempts (10)'), 500),
                   locked_by = NULL,
                   claimed_at = NULL,
                   updated_at = now()
             WHERE id = p_id AND merchant_id = v_merchant_id;
        ELSE
            -- Exponential backoff with random jitter: (2^attempt * 5s) + random(1..5s), capped at 5 mins
            v_jitter_secs := 1 + floor(random() * 5)::integer;
            v_delay_interval := LEAST(
                INTERVAL '300 seconds',
                (INTERVAL '5 seconds' * (2 ^ GREATEST(1, v_row.attempts))) + (v_jitter_secs * INTERVAL '1 second')
            );

            UPDATE public.sync_outbox
               SET status = 'failed',
                   last_error = LEFT(COALESCE(p_error, 'error'), 500),
                   next_attempt_at = now() + v_delay_interval,
                   locked_by = NULL,
                   claimed_at = NULL,
                   updated_at = now()
             WHERE id = p_id AND merchant_id = v_merchant_id;
        END IF;
    END IF;
END;
$$;

-- 8. Dead-letter queue replay function
CREATE OR REPLACE FUNCTION public.requeue_sync_outbox_dlq(
    p_job_ids UUID[] DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
    v_count INTEGER := 0;
BEGIN
    IF v_merchant_id IS NULL THEN
        RETURN 0;
    END IF;

    UPDATE public.sync_outbox
       SET status = 'pending',
           attempts = 0,
           next_attempt_at = now(),
           locked_by = NULL,
           claimed_at = NULL,
           last_error = 'Requeued from DLQ at ' || now()::text,
           updated_at = now()
     WHERE merchant_id = v_merchant_id
       AND status = 'dead_letter'
       AND (p_job_ids IS NULL OR id = ANY(p_job_ids));

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- 9. Grants
REVOKE ALL ON FUNCTION public.enqueue_sync_outbox(TEXT, TEXT, JSONB, UUID, UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_sync_outbox(INTEGER, UUID, TEXT[], TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_sync_outbox(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.requeue_sync_outbox_dlq(UUID[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.enqueue_sync_outbox(TEXT, TEXT, JSONB, UUID, UUID, INTEGER) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_sync_outbox(INTEGER, UUID, TEXT[], TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_sync_outbox(UUID, BOOLEAN, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.requeue_sync_outbox_dlq(UUID[]) TO authenticated, service_role;

COMMIT;
