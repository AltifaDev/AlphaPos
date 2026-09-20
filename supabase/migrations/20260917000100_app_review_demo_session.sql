-- App Review demo session verification.
--
-- CAPTCHA remains enabled for normal GoTrue password sign-ins.  This function
-- is callable only with the service-role key from the narrowly-scoped Edge
-- Function, and verifies only the non-production App Review demo account.

BEGIN;

CREATE OR REPLACE FUNCTION public.verify_app_review_demo_credentials(
    p_email TEXT,
    p_password TEXT
)
RETURNS TABLE (
    user_id UUID,
    email TEXT,
    email_confirmed BOOLEAN,
    app_metadata JSONB,
    user_metadata JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions, pg_temp
AS $$
BEGIN
    IF lower(btrim(COALESCE(p_email, ''))) <> 'appreview@alphaposweb.com'
       OR COALESCE(p_password, '') = '' THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT u.id,
           u.email,
           u.email_confirmed_at IS NOT NULL,
           COALESCE(u.raw_app_meta_data, '{}'::jsonb),
           COALESCE(u.raw_user_meta_data, '{}'::jsonb)
      FROM auth.users AS u
     WHERE lower(u.email) = 'appreview@alphaposweb.com'
       AND u.email_confirmed_at IS NOT NULL
       AND u.encrypted_password = crypt(p_password, u.encrypted_password)
     LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_app_review_demo_credentials(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_app_review_demo_credentials(TEXT, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_app_review_demo_credentials(TEXT, TEXT) TO service_role;

COMMIT;
