BEGIN;

ALTER TABLE public.merchant_devices
    ADD COLUMN IF NOT EXISTS credential_hash text,
    ADD COLUMN IF NOT EXISTS revoked_at timestamptz;

ALTER TABLE public.merchants
    ADD COLUMN IF NOT EXISTS terms_version text,
    ADD COLUMN IF NOT EXISTS privacy_version text,
    ADD COLUMN IF NOT EXISTS consented_at timestamptz,
    ADD COLUMN IF NOT EXISTS billing_cycle text,
    ALTER COLUMN subscription_status SET DEFAULT 'pending_payment';

CREATE TABLE IF NOT EXISTS public.merchant_onboarding_requests (
    idempotency_key uuid PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    merchant_id uuid NOT NULL UNIQUE REFERENCES public.merchants(id) ON DELETE CASCADE,
    device_id uuid NOT NULL UNIQUE REFERENCES public.merchant_devices(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.protect_subscription_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_role text;
BEGIN
    v_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role', '');
    IF v_role <> 'service_role' AND (
        NEW.subscription_status IS DISTINCT FROM OLD.subscription_status OR
        NEW.subscription_expires_at IS DISTINCT FROM OLD.subscription_expires_at
    ) THEN
        RAISE EXCEPTION 'Subscription state is payment-provider controlled' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_subscription_state ON public.merchants;
CREATE TRIGGER protect_subscription_state
BEFORE UPDATE ON public.merchants
FOR EACH ROW EXECUTE FUNCTION public.protect_subscription_state();

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
        );

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

    RETURN QUERY SELECT v_merchant_id, r.device_id, m.subscription_status
    FROM public.merchant_onboarding_requests r
    JOIN public.merchants m ON m.id = r.merchant_id
    WHERE r.merchant_id = v_merchant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_merchant_onboarding(
    uuid,text,text,text,text,text,text,text,text,text,text,text,timestamptz,uuid,uuid,text,text,text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_merchant_onboarding(
    uuid,text,text,text,text,text,text,text,text,text,text,text,timestamptz,uuid,uuid,text,text,text
) TO service_role;

COMMIT;
