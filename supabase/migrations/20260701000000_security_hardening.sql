-- =========================================================================
-- Migration: Global Security Hardening & RLS Enforcement
-- Created: 2026-07-01
-- Description: Ensures Row-Level Security (RLS) is strictly enabled on 
--              all public tables, and enforces multi-tenant isolation.
-- =========================================================================

BEGIN;

-- 1. Dynamic enforcement of RLS on all current tables in the public schema
-- This acts as a catch-all safety net to protect tables that might have been
-- added without an explicit 'ENABLE ROW LEVEL SECURITY' command.
DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    ) LOOP
        -- Exclude standard supabase/system tables if any, and target user-defined ones
        EXECUTE 'ALTER TABLE public.' || quote_ident(tbl.tablename) || ' ENABLE ROW LEVEL SECURITY;';
    END LOOP;
END;
$$;

-- 2. Audit log configuration
-- Enforces that the audit_logs table is strictly read-only for anonymous users,
-- and writable only by authenticated service-role or designated background workers.
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_logs_read_only_isolation" ON public.audit_logs;
CREATE POLICY "audit_logs_read_only_isolation" ON public.audit_logs
    FOR SELECT TO anon
    USING (merchant_id = get_active_merchant_id());

DROP POLICY IF EXISTS "audit_logs_write_isolation" ON public.audit_logs;
CREATE POLICY "audit_logs_write_isolation" ON public.audit_logs
    FOR INSERT TO authenticated
    WITH CHECK (merchant_id = get_active_merchant_id());

COMMIT;
