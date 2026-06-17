-- Migration 010: Restore HTTP Header Fallback in get_merchant_id()
-- This enables customer-order-web (which does not have device secrets to obtain JWTs)
-- and the local Python sync server to query/insert data via Supabase using the x-merchant-id HTTP header.
-- Meanwhile, iPad and iPhone apps will continue to use the cryptographically signed JWT.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_merchant_id() 
RETURNS UUID AS $$
DECLARE
    v_merchant_id TEXT;
    v_claims JSON;
BEGIN
    -- 1. Attempt to read from JWT Claims
    BEGIN
        v_claims := current_setting('request.jwt.claims', true)::json;
    EXCEPTION WHEN OTHERS THEN
        v_claims := NULL;
    END;

    IF v_claims IS NOT NULL THEN
        -- standard Supabase Auth app_metadata claim path
        v_merchant_id := v_claims->'app_metadata'->>'merchant_id';
        
        -- fallback direct claim path (used by our custom Edge Function JWT)
        IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
            v_merchant_id := v_claims->>'merchant_id';
        END IF;
    END IF;
    
    -- 2. Fallback to custom HTTP request header (required for anonymous customer web app and sync server)
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

COMMIT;
