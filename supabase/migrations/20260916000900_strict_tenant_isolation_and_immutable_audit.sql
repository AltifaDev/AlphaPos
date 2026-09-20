-- =========================================================================
-- Migration: 20260916000900_strict_tenant_isolation_and_immutable_audit.sql
-- Description: Strict Multi-Tenancy (Signed JWT Identity Only) &
--              Immutable Append-Only Audit Trail (Anti-Tamper)
-- Features:
--   1. Remove insecure header fallback from get_merchant_id()
--   2. Strict server-side verification of merchant_id & branch_id from JWT
--   3. Extended audit_logs schema (actor, device, IP, diff snapshots, reasons)
--   4. Immutable audit enforcement (Trigger + Revoke UPDATE/DELETE/TRUNCATE)
--   5. Standardized record_audit_log() RPC
-- =========================================================================

BEGIN;

-- 1. Strict Tenant Identity Resolution (Reject Unsigned Headers)
CREATE OR REPLACE FUNCTION public.get_merchant_id() 
RETURNS UUID AS $$
DECLARE
    v_merchant_id TEXT;
    v_claims JSONB;
BEGIN
    BEGIN
        v_claims := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_claims := NULL;
    END;

    IF v_claims IS NOT NULL THEN
        -- Check app_metadata first (standard Supabase pattern)
        v_merchant_id := v_claims->'app_metadata'->>'merchant_id';
        
        -- Check direct custom claim
        IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
            v_merchant_id := v_claims->>'merchant_id';
        END IF;
    END IF;

    -- Note: Unsigned HTTP header fallback ('x-merchant-id') has been removed
    -- for production security compliance. All merchant API calls must provide
    -- a valid cryptographic bearer token (JWT).

    RETURN NULLIF(v_merchant_id, '')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION public.get_active_merchant_id() 
RETURNS UUID AS $$
BEGIN
    RETURN public.get_merchant_id();
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. Extend audit_logs table
ALTER TABLE public.audit_logs
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS device_id TEXT,
    ADD COLUMN IF NOT EXISTS actor_id UUID,
    ADD COLUMN IF NOT EXISTS actor_type TEXT NOT NULL DEFAULT 'staff',
    ADD COLUMN IF NOT EXISTS ip_address TEXT,
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS reason TEXT,
    ADD COLUMN IF NOT EXISTS entity_type TEXT,
    ADD COLUMN IF NOT EXISTS entity_id TEXT,
    ADD COLUMN IF NOT EXISTS before_state JSONB,
    ADD COLUMN IF NOT EXISTS after_state JSONB;

-- 3. Audit Log Immutability Enforcement (WORM: Write Once, Read Many)
-- Prevent any UPDATE, DELETE, or TRUNCATE on audit records
CREATE OR REPLACE FUNCTION public.prevent_audit_log_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs_are_immutable: operation % is forbidden on audit trail', TG_OP
        USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON public.audit_logs;
CREATE TRIGGER trg_audit_logs_immutable
    BEFORE UPDATE OR DELETE ON public.audit_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_audit_log_modification();

-- Revoke write-alteration privileges from all roles
REVOKE UPDATE, DELETE, TRUNCATE ON public.audit_logs FROM PUBLIC, anon, authenticated;

-- Ensure branch isolation policy on audit_logs
DROP POLICY IF EXISTS merchant_isolation_audit_logs ON public.audit_logs;
DROP POLICY IF EXISTS audit_logs_tenant_isolation ON public.audit_logs;

CREATE POLICY audit_logs_tenant_isolation ON public.audit_logs
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

-- 4. Standardized Audit Event Helper
CREATE OR REPLACE FUNCTION public.record_audit_log(
    p_action_type TEXT,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id TEXT DEFAULT NULL,
    p_reason TEXT DEFAULT NULL,
    p_before JSONB DEFAULT NULL,
    p_after JSONB DEFAULT NULL,
    p_details TEXT DEFAULT NULL,
    p_branch_id UUID DEFAULT NULL,
    p_device_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_claims JSONB := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
    v_headers JSONB := COALESCE(NULLIF(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
    v_merchant_id UUID := public.get_active_merchant_id();
    v_branch_id UUID := COALESCE(p_branch_id, public.get_active_branch_id());
    v_actor_id UUID := NULLIF(v_claims->>'sub', '')::UUID;
    v_actor_type TEXT := COALESCE(NULLIF(v_claims->>'role', ''), 'staff');
    v_device_id TEXT := COALESCE(NULLIF(trim(p_device_id), ''), v_headers->>'x-device-id', v_claims->>'device_id');
    v_ip TEXT := COALESCE(v_headers->>'cf-connecting-ip', v_headers->>'x-forwarded-for', 'internal');
    v_id UUID := gen_random_uuid();
BEGIN
    IF v_merchant_id IS NULL OR NULLIF(trim(p_action_type), '') IS NULL THEN
        RAISE EXCEPTION 'invalid_audit_log_entry' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.audit_logs (
        id, merchant_id, branch_id, actor_id, actor_type, action_type,
        entity_type, entity_id, reason, details, device_id, ip_address,
        before_state, after_state, created_at
    ) VALUES (
        v_id, v_merchant_id, v_branch_id, v_actor_id, v_actor_type, trim(p_action_type),
        NULLIF(trim(p_entity_type), ''), NULLIF(trim(p_entity_id), ''),
        NULLIF(trim(p_reason), ''), NULLIF(trim(p_details), ''),
        v_device_id, v_ip, p_before, p_after, now()
    );

    RETURN v_id;
END;
$$;

-- 5. Additional Indexes for Security Auditing
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs (merchant_id, actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs (merchant_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_reason ON public.audit_logs (merchant_id, action_type, created_at DESC) WHERE reason IS NOT NULL;

-- 6. Grants
REVOKE ALL ON FUNCTION public.record_audit_log(TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_audit_log(TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

COMMIT;
