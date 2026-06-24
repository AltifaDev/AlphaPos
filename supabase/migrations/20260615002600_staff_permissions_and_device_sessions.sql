-- =========================================================================
-- Migration 023: Staff Permissions and Device Sessions
-- Created: 2026-06-17
-- Description: Adds POS-grade staff permission and trusted device primitives.
--              Merchant authentication remains tenant-level; staff passcodes
--              authorize the active operator on a shared POS device.
-- =========================================================================

BEGIN;

-- Role permission catalog. The app also keeps a SwiftData copy for offline use.
CREATE TABLE IF NOT EXISTS public.role_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    role VARCHAR(50) NOT NULL,
    permission_key TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_role_permission UNIQUE (merchant_id, role, permission_key)
);

-- Trusted POS devices bound to one merchant and optionally one branch.
CREATE TABLE IF NOT EXISTS public.merchant_devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    device_name TEXT NOT NULL,
    device_type TEXT NOT NULL DEFAULT 'pos_register',
    device_fingerprint_hash TEXT,
    is_trusted BOOLEAN NOT NULL DEFAULT TRUE,
    last_seen_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Staff sessions record who was operating the shared POS device.
CREATE TABLE IF NOT EXISTS public.staff_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    device_id UUID REFERENCES public.merchant_devices(id) ON DELETE SET NULL,
    employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    role VARCHAR(50),
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ended_at TIMESTAMP WITH TIME ZONE,
    ended_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Passcode policy settings are merchant-scoped and can be cached locally.
CREATE TABLE IF NOT EXISTS public.security_policies (
    merchant_id UUID PRIMARY KEY REFERENCES public.merchants(id) ON DELETE CASCADE,
    passcode_min_length INTEGER NOT NULL DEFAULT 4 CHECK (passcode_min_length BETWEEN 4 AND 8),
    passcode_max_attempts INTEGER NOT NULL DEFAULT 5 CHECK (passcode_max_attempts BETWEEN 3 AND 10),
    lockout_minutes INTEGER NOT NULL DEFAULT 5 CHECK (lockout_minutes BETWEEN 1 AND 60),
    staff_session_timeout_minutes INTEGER NOT NULL DEFAULT 15 CHECK (staff_session_timeout_minutes BETWEEN 1 AND 480),
    require_manager_override_for_refund BOOLEAN NOT NULL DEFAULT TRUE,
    require_manager_override_for_void BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_policies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_role_permissions" ON public.role_permissions;
CREATE POLICY "merchant_isolation_role_permissions" ON public.role_permissions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

DROP POLICY IF EXISTS "merchant_isolation_merchant_devices" ON public.merchant_devices;
CREATE POLICY "merchant_isolation_merchant_devices" ON public.merchant_devices
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

DROP POLICY IF EXISTS "merchant_isolation_staff_sessions" ON public.staff_sessions;
CREATE POLICY "merchant_isolation_staff_sessions" ON public.staff_sessions
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

DROP POLICY IF EXISTS "merchant_isolation_security_policies" ON public.security_policies;
CREATE POLICY "merchant_isolation_security_policies" ON public.security_policies
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

COMMIT;
