-- PostgreSQL SQL migration script to support Merchant Login and Multi-Tenancy
-- Creates merchant_users table, public.get_merchant_id() claims extractor,
-- points get_active_merchant_id() to public.get_merchant_id(), and sets up RLS policies.

BEGIN;

-- 1. Create the merchant_users table referencing auth.users(id)
CREATE TABLE IF NOT EXISTS merchant_users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role VARCHAR(50) DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_merchant_users_merchant ON merchant_users (merchant_id);

-- 2. Define public.get_merchant_id() to read claims from JWT or request header
CREATE OR REPLACE FUNCTION public.get_merchant_id() 
RETURNS UUID AS $$
DECLARE
    v_merchant_id TEXT;
    v_claims JSON;
BEGIN
    -- A. Attempt to read from JWT Claims
    BEGIN
        v_claims := current_setting('request.jwt.claims', true)::json;
    EXCEPTION WHEN OTHERS THEN
        v_claims := NULL;
    END;

    IF v_claims IS NOT NULL THEN
        -- standard Supabase Auth app_metadata claim path
        v_merchant_id := v_claims->'app_metadata'->>'merchant_id';
        
        -- fallback direct claim path
        IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
            v_merchant_id := v_claims->>'merchant_id';
        END IF;
    END IF;
    
    -- B. Fallback to custom HTTP request header
    IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
        BEGIN
            v_merchant_id := current_setting('request.headers', true)::json->>'x-merchant-id';
        EXCEPTION WHEN OTHERS THEN
            v_merchant_id := NULL;
        END;
    END IF;
    
    RETURN NULLIF(v_merchant_id, '')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Point public.get_active_merchant_id() to public.get_merchant_id()
CREATE OR REPLACE FUNCTION public.get_active_merchant_id() 
RETURNS UUID AS $$
BEGIN
    RETURN public.get_merchant_id();
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. Enable RLS and define policies on merchant_users
ALTER TABLE merchant_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_merchant_users" ON merchant_users;

CREATE POLICY "merchant_isolation_merchant_users" ON merchant_users
    FOR SELECT TO public USING (merchant_id = public.get_merchant_id());

COMMIT;
