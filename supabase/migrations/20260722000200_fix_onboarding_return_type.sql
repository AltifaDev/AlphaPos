BEGIN;

-- Fix: RETURN QUERY must cast varchar subscription_status to text to match
-- RETURNS TABLE (... subscription_status text). Without the cast Postgres raises:
-- "structure of query does not match function result type"
CREATE OR REPLACE FUNCTION public.complete_merchant_onboarding(
    p_user_id uuid,
    p_email text,
    p_shop_name text,
    p_first_name text,
    p_last_name text,
    p_shop_phone text,
    p_currency text,
    p_tax_id text,
    p_subscription_tier text,
    p_billing_cycle text,
    p_terms_version text,
    p_privacy_version text,
    p_consented_at timestamptz,
    p_idempotency_key uuid,
    p_device_id uuid,
    p_device_name text,
    p_device_fingerprint_hash text,
    p_device_credential_hash text
)
RETURNS TABLE (merchant_id uuid, device_id uuid, subscription_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_merchant_id uuid;
    v_existing_device_merchant uuid;
BEGIN
    IF p_user_id IS NULL OR p_idempotency_key IS NULL OR p_device_id IS NULL THEN
        RAISE EXCEPTION 'Missing onboarding identity';
    END IF;
    IF p_terms_version IS NULL OR p_privacy_version IS NULL OR p_consented_at IS NULL THEN
        RAISE EXCEPTION 'Terms and privacy acceptance are required';
    END IF;
    IF p_subscription_tier NOT IN ('offline_perpetual', 'offline_subscription', 'online_subscription') THEN
        RAISE EXCEPTION 'Invalid subscription tier';
    END IF;
    IF p_billing_cycle NOT IN ('monthly', 'annual', 'perpetual') THEN
        RAISE EXCEPTION 'Invalid billing cycle';
    END IF;

    SELECT r.merchant_id INTO v_merchant_id
    FROM public.merchant_onboarding_requests r
    WHERE r.idempotency_key = p_idempotency_key OR r.user_id = p_user_id
    LIMIT 1;

    IF v_merchant_id IS NULL THEN
        SELECT d.merchant_id INTO v_existing_device_merchant
        FROM public.merchant_devices d
        WHERE d.id = p_device_id;

        IF v_existing_device_merchant IS NOT NULL THEN
            RAISE EXCEPTION 'Device already registered to another merchant'
                USING ERRCODE = '23505';
        END IF;

        INSERT INTO public.merchants (
            name, email, phone, currency, tax_id, tax_rate, tax_type,
            subscription_tier, subscription_status, subscription_expires_at,
            billing_cycle, terms_version, privacy_version, consented_at
        ) VALUES (
            btrim(p_shop_name), lower(btrim(p_email)), nullif(btrim(p_shop_phone), ''),
            upper(btrim(p_currency)), nullif(btrim(p_tax_id), ''), 7.0, 'inclusive',
            p_subscription_tier, 'pending_payment', NULL,
            p_billing_cycle, p_terms_version, p_privacy_version, p_consented_at
        ) RETURNING id INTO v_merchant_id;

        INSERT INTO public.merchant_users (id, merchant_id, first_name, last_name, role)
        VALUES (p_user_id, v_merchant_id, btrim(p_first_name), btrim(p_last_name), 'owner');

        INSERT INTO public.merchant_devices (
            id, merchant_id, device_name, device_type, device_fingerprint_hash,
            credential_hash, is_trusted, last_seen_at
        ) VALUES (
            p_device_id, v_merchant_id, btrim(p_device_name), 'pos_register',
            nullif(p_device_fingerprint_hash, ''), p_device_credential_hash, TRUE, now()
        )
        ON CONFLICT (id) DO UPDATE SET
            merchant_id = EXCLUDED.merchant_id,
            device_name = EXCLUDED.device_name,
            device_fingerprint_hash = EXCLUDED.device_fingerprint_hash,
            credential_hash = EXCLUDED.credential_hash,
            is_trusted = TRUE,
            revoked_at = NULL,
            last_seen_at = now(),
            updated_at = now();

        INSERT INTO public.merchant_onboarding_requests (
            idempotency_key, user_id, merchant_id, device_id
        ) VALUES (p_idempotency_key, p_user_id, v_merchant_id, p_device_id);
    ELSE
        UPDATE public.merchant_devices d
        SET credential_hash = p_device_credential_hash,
            device_name = btrim(p_device_name),
            device_fingerprint_hash = nullif(p_device_fingerprint_hash, ''),
            revoked_at = NULL,
            is_trusted = TRUE,
            updated_at = now()
        FROM public.merchant_onboarding_requests r
        WHERE r.merchant_id = v_merchant_id AND d.id = r.device_id;
    END IF;

    RETURN QUERY
    SELECT v_merchant_id, r.device_id, m.subscription_status::text
    FROM public.merchant_onboarding_requests r
    JOIN public.merchants m ON m.id = r.merchant_id
    WHERE r.merchant_id = v_merchant_id;
END;
$$;

COMMIT;
