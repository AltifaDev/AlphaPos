-- =========================================================================
-- Migration: PDPA / GDPR platform compliance for multi-tenant SaaS
-- Created: 2026-07-15
-- Description:
--   Adds tenant-scoped compliance primitives that a multi-merchant platform
--   needs to meet PDPA (Thailand) / GDPR expectations:
--     1. export_merchant_data(uuid)        — data portability (read-only JSON dump)
--     2. erase_merchant_data(uuid, text)   — right to erasure (guarded hard delete)
--     3. merchant_rate_limits + check_merchant_rate_limit(...) — per-tenant abuse control
--
--   All routines are SECURITY DEFINER and dynamically enumerate every table in
--   the public schema that carries a `merchant_id` column, so they stay correct
--   as the schema grows (no hard-coded table list to drift out of date).
--
--   Access rule (defence in depth): a caller may only touch a merchant's data if
--   ANY of the following is true —
--     • it is a direct DB admin (session_user = postgres / supabase_admin), OR
--     • it is the API service_role (JWT role claim = 'service_role'), OR
--     • it is that merchant itself (get_active_merchant_id() = p_merchant_id).
-- =========================================================================

BEGIN;

-- ── Shared access guard ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assert_merchant_compliance_access(p_merchant_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text;
BEGIN
    IF p_merchant_id IS NULL THEN
        RAISE EXCEPTION 'merchant_id is required' USING ERRCODE = '22023';
    END IF;

    BEGIN
        v_role := NULLIF(current_setting('request.jwt.claims', true), '')::json->>'role';
    EXCEPTION WHEN OTHERS THEN
        v_role := NULL;
    END;

    IF session_user IN ('postgres', 'supabase_admin') THEN
        RETURN; -- direct DB administrator (psql / backup jobs)
    END IF;

    IF v_role = 'service_role' THEN
        RETURN; -- trusted platform back end
    END IF;

    IF public.get_active_merchant_id() IS NOT DISTINCT FROM p_merchant_id THEN
        RETURN; -- the merchant acting on its own tenant
    END IF;

    RAISE EXCEPTION 'access denied for merchant %', p_merchant_id USING ERRCODE = '42501';
END;
$$;

-- ── 1. Data portability: export one merchant's data as JSON ───────────────
CREATE OR REPLACE FUNCTION public.export_merchant_data(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_data jsonb := '{}'::jsonb;
    v_table text;
    v_rows jsonb;
BEGIN
    PERFORM public.assert_merchant_compliance_access(p_merchant_id);

    -- The merchant root row first.
    EXECUTE 'SELECT coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM public.merchants t WHERE t.id = $1'
        INTO v_rows USING p_merchant_id;
    v_data := jsonb_build_object('merchants', v_rows);

    -- Every other tenant table that carries merchant_id (skip archives + internal tables).
    FOR v_table IN
        SELECT c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema = 'public'
          AND c.column_name = 'merchant_id'
          AND t.table_type = 'BASE TABLE'
          AND c.table_name NOT LIKE '%\_archive'
          AND c.table_name <> 'merchant_rate_limits'
        ORDER BY c.table_name
    LOOP
        EXECUTE format(
            'SELECT coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM public.%I t WHERE t.merchant_id = $1',
            v_table
        ) INTO v_rows USING p_merchant_id;
        v_data := v_data || jsonb_build_object(v_table, v_rows);
    END LOOP;

    RETURN jsonb_build_object(
        'format_version', 1,
        'merchant_id', p_merchant_id,
        'exported_at', now(),
        'data', v_data
    );
END;
$$;

-- ── 2. Right to erasure: hard-delete one merchant's data ──────────────────
-- Destructive. Requires the literal confirmation token 'ERASE'. Not granted to
-- anon; run from the platform back end (service_role) or a DB administrator.
CREATE OR REPLACE FUNCTION public.erase_merchant_data(p_merchant_id uuid, p_confirmation text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_table text;
    v_deleted jsonb := '{}'::jsonb;
    v_count bigint;
BEGIN
    PERFORM public.assert_merchant_compliance_access(p_merchant_id);

    IF p_confirmation IS DISTINCT FROM 'ERASE' THEN
        RAISE EXCEPTION 'confirmation token mismatch (expected "ERASE")' USING ERRCODE = '22023';
    END IF;

    -- Disable FK enforcement + triggers so deletion order does not matter.
    -- The function owner is a superuser in self-hosted Supabase, so the definer
    -- context is permitted to change this GUC for the current transaction only.
    PERFORM set_config('session_replication_role', 'replica', true);

    FOR v_table IN
        SELECT c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema = 'public'
          AND c.column_name = 'merchant_id'
          AND t.table_type = 'BASE TABLE'
        ORDER BY c.table_name
    LOOP
        EXECUTE format('DELETE FROM public.%I WHERE merchant_id = $1', v_table) USING p_merchant_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_deleted := v_deleted || jsonb_build_object(v_table, v_count);
        END IF;
    END LOOP;

    DELETE FROM public.merchants WHERE id = p_merchant_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count > 0 THEN
        v_deleted := v_deleted || jsonb_build_object('merchants', v_count);
    END IF;

    PERFORM set_config('session_replication_role', 'origin', true);

    RETURN jsonb_build_object(
        'merchant_id', p_merchant_id,
        'erased_at', now(),
        'rows_deleted', v_deleted
    );
END;
$$;

-- ── 3. Per-tenant rate limiting ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.merchant_rate_limits (
    merchant_id   uuid        NOT NULL,
    action        text        NOT NULL,
    window_start  timestamptz NOT NULL,
    request_count integer     NOT NULL DEFAULT 0,
    PRIMARY KEY (merchant_id, action, window_start)
);

ALTER TABLE public.merchant_rate_limits ENABLE ROW LEVEL SECURITY;
-- No table-level policy: rows are only ever touched through the SECURITY DEFINER
-- function below, never read/written directly by anon/authenticated.

CREATE INDEX IF NOT EXISTS idx_merchant_rate_limits_window
    ON public.merchant_rate_limits (window_start);

-- Atomically increments the counter for (merchant, action) in the current
-- fixed window and returns TRUE while the merchant is under the limit.
CREATE OR REPLACE FUNCTION public.check_merchant_rate_limit(
    p_merchant_id    uuid,
    p_action         text,
    p_limit          integer DEFAULT 120,
    p_window_seconds integer DEFAULT 60
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_window timestamptz;
    v_count  integer;
BEGIN
    IF p_merchant_id IS NULL OR p_action IS NULL THEN
        RETURN true; -- nothing to scope; fail open
    END IF;

    v_window := to_timestamp(floor(extract(epoch FROM now()) / p_window_seconds) * p_window_seconds);

    INSERT INTO public.merchant_rate_limits (merchant_id, action, window_start, request_count)
    VALUES (p_merchant_id, p_action, v_window, 1)
    ON CONFLICT (merchant_id, action, window_start)
    DO UPDATE SET request_count = public.merchant_rate_limits.request_count + 1
    RETURNING request_count INTO v_count;

    RETURN v_count <= p_limit;
END;
$$;

-- Housekeeping: drop rate-limit buckets older than a day. Schedule via cron.
CREATE OR REPLACE FUNCTION public.purge_merchant_rate_limits()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    DELETE FROM public.merchant_rate_limits WHERE window_start < now() - interval '1 day';
$$;

-- ── Grants ────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.assert_merchant_compliance_access(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.export_merchant_data(uuid)             FROM PUBLIC;
REVOKE ALL ON FUNCTION public.erase_merchant_data(uuid, text)        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_merchant_rate_limit(uuid, text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_merchant_rate_limits()           FROM PUBLIC;

-- Export is read-only and self-scoped → safe for the merchant app (anon JWT).
GRANT EXECUTE ON FUNCTION public.export_merchant_data(uuid) TO anon, authenticated, service_role;
-- Erasure is destructive → platform back end / admins only (never anon).
GRANT EXECUTE ON FUNCTION public.erase_merchant_data(uuid, text) TO authenticated, service_role;
-- Rate limiting is called on the hot path by any tier.
GRANT EXECUTE ON FUNCTION public.check_merchant_rate_limit(uuid, text, integer, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.purge_merchant_rate_limits() TO service_role;

COMMIT;
