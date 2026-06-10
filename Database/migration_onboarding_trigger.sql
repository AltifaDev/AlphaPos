-- PostgreSQL SQL migration script to automate Multi-Tenant Merchant onboarding
-- Creates the public.handle_new_merchant_user() trigger function and binds it to auth.users.

BEGIN;

-- 1. Create or replace the onboarding trigger function
CREATE OR REPLACE FUNCTION public.handle_new_merchant_user()
RETURNS TRIGGER AS $$
DECLARE
    v_merchant_id UUID;
    v_first_name TEXT;
    v_last_name TEXT;
BEGIN
    -- Check if a merchant with the registering email already exists (case-insensitive)
    SELECT id INTO v_merchant_id 
    FROM public.merchants 
    WHERE LOWER(email) = LOWER(new.email)
    LIMIT 1;

    -- If not, create a new merchant
    IF v_merchant_id IS NULL THEN
        INSERT INTO public.merchants (name, email)
        VALUES (
            COALESCE(new.raw_user_meta_data->>'store_name', 'My New POS Shop'),
            new.email
        )
        RETURNING id INTO v_merchant_id;
    END IF;

    -- B. Extract owner name from user metadata
    v_first_name := COALESCE(new.raw_user_meta_data->>'first_name', 'Owner');
    v_last_name := COALESCE(new.raw_user_meta_data->>'last_name', 'User');

    -- C. Link to merchant_users table (works in AFTER INSERT as auth.users row exists)
    INSERT INTO public.merchant_users (id, merchant_id, first_name, last_name, role)
    VALUES (new.id, v_merchant_id, v_first_name, v_last_name, 'owner')
    ON CONFLICT (id) DO UPDATE 
    SET merchant_id = EXCLUDED.merchant_id,
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        role = EXCLUDED.role;

    -- D. Inject merchant_id custom claim into app_metadata (raw_app_meta_data)
    UPDATE auth.users
    SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('merchant_id', v_merchant_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Bind the trigger to auth.users table as AFTER INSERT
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_merchant_user();

COMMIT;
