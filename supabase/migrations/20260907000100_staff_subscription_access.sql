BEGIN;

-- One policy for companion-device access. The main register may still open
-- billing during pending/expired states; that does not grant staff access.
CREATE OR REPLACE FUNCTION public.staff_subscription_access_reason(
    p_tier text, p_status text, p_expires_at timestamptz, p_now timestamptz
) RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN lower(btrim(p_tier)) IN ('offline_perpetual', 'offline_subscription')
            THEN 'plan_not_supported'
        WHEN p_tier IS NULL OR lower(btrim(p_tier)) <> 'online_subscription'
            THEN 'invalid_subscription'
        WHEN lower(btrim(p_status)) = 'pending_payment' THEN 'pending_payment'
        WHEN lower(btrim(p_status)) = 'expired' THEN 'expired'
        WHEN lower(btrim(p_status)) IN ('suspended', 'cancelled', 'canceled', 'inactive') THEN 'inactive'
        WHEN p_status IS NULL OR lower(btrim(p_status)) NOT IN ('active', 'trial')
            THEN 'invalid_subscription'
        WHEN p_expires_at IS NULL OR NOT isfinite(p_expires_at) OR p_now IS NULL
            THEN 'invalid_subscription'
        WHEN p_expires_at <= p_now THEN
            CASE WHEN lower(btrim(p_status)) = 'trial' THEN 'trial_expired' ELSE 'expired' END
        ELSE 'allowed'
    END;
$$;

CREATE OR REPLACE FUNCTION public.get_staff_subscription_access()
RETURNS TABLE (merchant_id uuid, reason text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
    SELECT m.id, public.staff_subscription_access_reason(
        m.subscription_tier::text, m.subscription_status::text,
        m.subscription_expires_at, statement_timestamp()
    )
    FROM public.merchants m
    WHERE m.id = public.get_active_merchant_id()
      AND m.id::text = COALESCE(
          NULLIF(current_setting('request.jwt.claims', true), '')::jsonb #>> '{app_metadata,merchant_id}',
          NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'merchant_id'
      );
$$;
REVOKE ALL ON FUNCTION public.staff_subscription_access_reason(text, text, timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_staff_subscription_access() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.staff_subscription_access_reason(text, text, timestamptz, timestamptz) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_staff_subscription_access() TO anon, authenticated, service_role;
NOTIFY pgrst, 'reload schema';
COMMIT;
