-- =========================================================================
-- Migration: 20260916001000_rate_limiting_and_monitoring_telemetry.sql
-- Description: Rate Limiting, Throttling & System Monitoring Telemetry
-- Features:
--   1. Tenant & branch sliding rate limiting (check_tenant_rate_limit)
--   2. Dynamic sync concurrency slots (acquire_sync_slot / release_sync_slot)
--   3. Deep system telemetry RPC: get_system_production_metrics()
--      (DB connection pool, lock waits, outbox lag, DLQ, 5xx/conflicts)
-- =========================================================================

BEGIN;

-- 1. Table for tracking active sync slots (concurrency throttle)
CREATE TABLE IF NOT EXISTS public.active_sync_slots (
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '60 seconds'),
    PRIMARY KEY (merchant_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_active_sync_slots_expiry
    ON public.active_sync_slots (expires_at);

ALTER TABLE public.active_sync_slots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.active_sync_slots FROM PUBLIC, anon, authenticated;

-- Acquire sync slot with concurrency ceiling per branch
CREATE OR REPLACE FUNCTION public.acquire_sync_slot(
    p_branch_id UUID DEFAULT NULL,
    p_device_id TEXT DEFAULT NULL,
    p_max_concurrent INTEGER DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
    v_branch_id UUID := COALESCE(p_branch_id, public.get_active_branch_id());
    v_device_id TEXT := COALESCE(NULLIF(trim(p_device_id), ''), 'device-' || substr(gen_random_uuid()::text, 1, 8));
    v_active_count INTEGER;
    v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_max_concurrent, 5), 50));
BEGIN
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('allowed', false, 'error', 'auth_required');
    END IF;

    -- Purge stale slots
    DELETE FROM public.active_sync_slots
     WHERE expires_at < now();

    -- Count active concurrent slots for this tenant & branch
    SELECT COUNT(*) INTO v_active_count
      FROM public.active_sync_slots
     WHERE merchant_id = v_merchant_id
       AND (v_branch_id IS NULL OR branch_id IS NULL OR branch_id = v_branch_id)
       AND device_id <> v_device_id;

    IF v_active_count >= v_limit THEN
        -- Concurrency limit reached; instruct device to backoff with jitter
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'branch_sync_concurrency_limit_reached',
            'active_count', v_active_count,
            'max_allowed', v_limit,
            'retry_after_seconds', 2 + floor(random() * 3)::integer
        );
    END IF;

    -- Reserve or refresh slot for 60 seconds
    INSERT INTO public.active_sync_slots (merchant_id, branch_id, device_id, acquired_at, expires_at)
    VALUES (v_merchant_id, v_branch_id, v_device_id, now(), now() + INTERVAL '60 seconds')
    ON CONFLICT (merchant_id, device_id)
    DO UPDATE SET branch_id = EXCLUDED.branch_id,
                  acquired_at = now(),
                  expires_at = now() + INTERVAL '60 seconds';

    RETURN jsonb_build_object(
        'allowed', true,
        'device_id', v_device_id,
        'active_count', (v_active_count + 1),
        'lease_seconds', 60
    );
END;
$$;

-- Release sync slot upon completion
CREATE OR REPLACE FUNCTION public.release_sync_slot(
    p_device_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
BEGIN
    IF v_merchant_id IS NOT NULL AND p_device_id IS NOT NULL THEN
        DELETE FROM public.active_sync_slots
         WHERE merchant_id = v_merchant_id AND device_id = trim(p_device_id);
    END IF;
END;
$$;

-- 2. Enhanced Tenant & Branch Rate Limiter
CREATE OR REPLACE FUNCTION public.check_tenant_rate_limit(
    p_action TEXT,
    p_limit INTEGER DEFAULT 120,
    p_window_seconds INTEGER DEFAULT 60,
    p_branch_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
    v_branch_id UUID := COALESCE(p_branch_id, public.get_active_branch_id());
    v_scoped_action TEXT;
BEGIN
    IF v_merchant_id IS NULL THEN
        RETURN true;
    END IF;

    v_scoped_action := CASE 
        WHEN v_branch_id IS NOT NULL THEN p_action || ':' || v_branch_id::text
        ELSE p_action 
    END;

    RETURN public.check_merchant_rate_limit(v_merchant_id, v_scoped_action, p_limit, p_window_seconds);
END;
$$;

-- 3. Production Health & Telemetry Metrics RPC
CREATE OR REPLACE FUNCTION public.get_system_production_metrics()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_claims JSONB := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
    v_merchant_id UUID := public.get_active_merchant_id();
    
    -- Connection metrics
    v_total_connections INTEGER := 0;
    v_active_connections INTEGER := 0;
    v_max_connections INTEGER := 100;
    v_pool_utilization_pct NUMERIC := 0.0;
    
    -- Lock wait metrics
    v_lock_wait_count INTEGER := 0;
    v_slow_query_count INTEGER := 0;
    
    -- Outbox metrics
    v_outbox_pending INTEGER := 0;
    v_outbox_processing INTEGER := 0;
    v_outbox_failed INTEGER := 0;
    v_outbox_dlq INTEGER := 0;
    v_oldest_pending_age_sec NUMERIC := 0;
    v_oldest_processing_age_sec NUMERIC := 0;
    
    -- Conflict & Security metrics
    v_conflicts_1h INTEGER := 0;
    v_voids_1h INTEGER := 0;
    v_refunds_1h INTEGER := 0;
    
    -- Evaluation
    v_status TEXT := 'healthy';
    v_alerts JSONB := '[]'::jsonb;
BEGIN
    -- Only allow platform admins or authenticated merchants
    IF v_merchant_id IS NULL AND (v_claims->>'role') NOT IN ('service_role', 'admin', 'supabase_admin') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
    END IF;

    -- Read database connection counts from pg_stat_activity safely
    BEGIN
        SELECT count(*), count(*) FILTER (WHERE state = 'active')
          INTO v_total_connections, v_active_connections
          FROM pg_stat_activity;

        SELECT setting::int INTO v_max_connections
          FROM pg_settings
         WHERE name = 'max_connections';
    EXCEPTION WHEN OTHERS THEN
        v_total_connections := 0;
        v_active_connections := 0;
        v_max_connections := 100;
    END;

    IF v_max_connections > 0 THEN
        v_pool_utilization_pct := round((v_total_connections::numeric / v_max_connections::numeric) * 100, 1);
    END IF;

    -- Check lock waits from pg_stat_activity
    BEGIN
        SELECT count(*)
          INTO v_lock_wait_count
          FROM pg_stat_activity
         WHERE wait_event_type = 'Lock' AND state = 'active';

        SELECT count(*)
          INTO v_slow_query_count
          FROM pg_stat_activity
         WHERE state = 'active' AND (now() - query_start) > INTERVAL '1 second';
    EXCEPTION WHEN OTHERS THEN
        v_lock_wait_count := 0;
        v_slow_query_count := 0;
    END;

    -- Outbox statistics (scoped to merchant if merchant token, or global if service_role)
    SELECT
        count(*) FILTER (WHERE status = 'pending'),
        count(*) FILTER (WHERE status = 'processing'),
        count(*) FILTER (WHERE status = 'failed'),
        count(*) FILTER (WHERE status = 'dead_letter'),
        COALESCE(EXTRACT(EPOCH FROM (now() - min(created_at) FILTER (WHERE status = 'pending'))), 0),
        COALESCE(EXTRACT(EPOCH FROM (now() - min(claimed_at) FILTER (WHERE status = 'processing'))), 0)
    INTO
        v_outbox_pending, v_outbox_processing, v_outbox_failed, v_outbox_dlq,
        v_oldest_pending_age_sec, v_oldest_processing_age_sec
    FROM public.sync_outbox
    WHERE (v_merchant_id IS NULL OR merchant_id = v_merchant_id);

    -- Conflict statistics in last 1 hour
    SELECT count(*) INTO v_conflicts_1h
      FROM public.sync_conflict_journal
     WHERE created_at > (now() - INTERVAL '1 hour')
       AND (v_merchant_id IS NULL OR merchant_id = v_merchant_id);

    -- Sensitive Audit Trail actions in last 1 hour
    SELECT
        count(*) FILTER (WHERE action_type IN ('item_void', 'order_cancel')),
        count(*) FILTER (WHERE action_type IN ('refund', 'order_refund'))
    INTO v_voids_1h, v_refunds_1h
    FROM public.audit_logs
    WHERE created_at > (now() - INTERVAL '1 hour')
      AND (v_merchant_id IS NULL OR merchant_id = v_merchant_id);

    -- Rule Evaluations & Health Alerts
    IF v_pool_utilization_pct >= 85 THEN
        v_status := 'critical';
        v_alerts := v_alerts || jsonb_build_object('level', 'critical', 'metric', 'pool_utilization', 'message', 'Connection pool near saturation (' || v_pool_utilization_pct || '%)');
    ELSIF v_pool_utilization_pct >= 70 THEN
        IF v_status <> 'critical' THEN v_status := 'warning'; END IF;
        v_alerts := v_alerts || jsonb_build_object('level', 'warning', 'metric', 'pool_utilization', 'message', 'Connection pool elevated (' || v_pool_utilization_pct || '%)');
    END IF;

    IF v_lock_wait_count > 3 THEN
        v_status := 'critical';
        v_alerts := v_alerts || jsonb_build_object('level', 'critical', 'metric', 'lock_waits', 'message', 'High lock contention: ' || v_lock_wait_count || ' queries blocked');
    END IF;

    IF v_outbox_dlq > 0 THEN
        IF v_status <> 'critical' THEN v_status := 'warning'; END IF;
        v_alerts := v_alerts || jsonb_build_object('level', 'warning', 'metric', 'dead_letter_queue', 'message', v_outbox_dlq || ' jobs in Dead-Letter Queue');
    END IF;

    IF v_oldest_processing_age_sec > 180 THEN
        IF v_status <> 'critical' THEN v_status := 'warning'; END IF;
        v_alerts := v_alerts || jsonb_build_object('level', 'warning', 'metric', 'outbox_lag', 'message', 'Stuck processing outbox job (' || round(v_oldest_processing_age_sec) || 's)');
    END IF;

    IF v_conflicts_1h > 20 THEN
        IF v_status <> 'critical' THEN v_status := 'warning'; END IF;
        v_alerts := v_alerts || jsonb_build_object('level', 'warning', 'metric', 'concurrency_conflicts', 'message', 'High optimistic lock conflicts (' || v_conflicts_1h || ' in last hour)');
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'overall_health', v_status,
        'timestamp', now(),
        'alerts', v_alerts,
        'database', jsonb_build_object(
            'total_connections', v_total_connections,
            'active_connections', v_active_connections,
            'max_connections', v_max_connections,
            'pool_utilization_pct', v_pool_utilization_pct,
            'lock_waits', v_lock_wait_count,
            'slow_queries_1s', v_slow_query_count
        ),
        'outbox_queue', jsonb_build_object(
            'pending', v_outbox_pending,
            'processing', v_outbox_processing,
            'failed', v_outbox_failed,
            'dead_letter', v_outbox_dlq,
            'oldest_pending_age_sec', round(v_oldest_pending_age_sec),
            'oldest_processing_age_sec', round(v_oldest_processing_age_sec)
        ),
        'concurrency_and_security', jsonb_build_object(
            'conflicts_last_hour', v_conflicts_1h,
            'voids_last_hour', v_voids_1h,
            'refunds_last_hour', v_refunds_1h
        )
    );
END;
$$;

-- 4. Grants
REVOKE ALL ON FUNCTION public.acquire_sync_slot(UUID, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.release_sync_slot(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_tenant_rate_limit(TEXT, INTEGER, INTEGER, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_system_production_metrics() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.acquire_sync_slot(UUID, TEXT, INTEGER) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_sync_slot(TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_tenant_rate_limit(TEXT, INTEGER, INTEGER, UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_system_production_metrics() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
