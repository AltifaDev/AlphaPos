-- Migration 009: Add device_secret_hash column to merchants table
-- This column stores a SHA-256 hash of the per-merchant device secret
-- used by the Edge Function `issue-merchant-token` to verify device identity
-- before issuing a JWT token.
--
-- The device_secret is set by the merchant owner during initial POS setup.
-- It is hashed before storage (SHA-256 hex). The plain-text secret is
-- stored securely on each device's Keychain and never transmitted in the clear
-- except during the token-issuance call (over TLS).
--
-- Run this migration BEFORE deploying the Edge Function.

BEGIN;

-- 1. Add device_secret_hash column (nullable — merchants without it skip verification)
ALTER TABLE merchants ADD COLUMN IF NOT EXISTS device_secret_hash TEXT;

-- 2. Ensure get_merchant_id() reads from JWT claims ONLY (no HTTP header fallback)
--    This is the security-hardened version. Any client that sends `x-merchant-id`
--    as an HTTP header will be ignored — only the cryptographically signed JWT
--    claim is trusted.
CREATE OR REPLACE FUNCTION public.get_merchant_id() 
RETURNS UUID AS $$
DECLARE
    v_merchant_id TEXT;
    v_claims JSON;
BEGIN
    -- Attempt to read from JWT Claims
    BEGIN
        v_claims := current_setting('request.jwt.claims', true)::json;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;

    IF v_claims IS NULL THEN
        RETURN NULL;
    END IF;

    -- Standard Supabase Auth app_metadata claim path
    v_merchant_id := v_claims->'app_metadata'->>'merchant_id';
    
    -- Fallback: direct claim path (used by our custom Edge Function JWT)
    IF v_merchant_id IS NULL OR v_merchant_id = '' THEN
        v_merchant_id := v_claims->>'merchant_id';
    END IF;
    
    RETURN NULLIF(v_merchant_id, '')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Ensure get_active_merchant_id() points to get_merchant_id()
CREATE OR REPLACE FUNCTION public.get_active_merchant_id() 
RETURNS UUID AS $$
BEGIN
    RETURN public.get_merchant_id();
END;
$$ LANGUAGE plpgsql STABLE;

COMMIT;
