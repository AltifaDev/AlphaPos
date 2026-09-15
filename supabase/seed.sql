-- Seed Merchants
INSERT INTO public.merchants (id, name, email, phone, currency, tax_rate, tax_type, device_secret_hash)
VALUES (
    '163350b0-056d-4d5e-b5d4-24e7aac5ab6d',
    'Default Local Merchant',
    'merchant@alphapos.com',
    '02-123-4567',
    'THB',
    7.00,
    'inclusive',
    'ddbbed716773b6ccd7e3fd1414d519cbc5b69943e625b16c107fadf908c65198'
) ON CONFLICT (id) DO NOTHING;

-- Seed Auth User (altifadev@gmail.com / Test1234)
INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    is_sso_user,
    is_anonymous,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
) VALUES (
    '00000000-0000-0000-0000-000000000000',
    '33333333-3333-3333-3333-333333333333',
    'authenticated',
    'authenticated',
    'altifadev@gmail.com',
    -- Bcrypt hash of 'Test1234'
    crypt('Test1234', gen_salt('bf')),
    now(),
    '{"provider": "email", "providers": ["email"], "merchant_id": "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"}',
    '{"full_name": "Altifa Dev"}',
    false,
    now(),
    now(),
    false,
    false,
    '',
    '',
    '',
    ''
) ON CONFLICT (id) DO NOTHING;

-- Seed Identity
INSERT INTO auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    created_at,
    updated_at
) VALUES (
    '44444444-4444-4444-4444-444444444444',
    '33333333-3333-3333-3333-333333333333',
    '33333333-3333-3333-3333-333333333333',
    '{"sub": "33333333-3333-3333-3333-333333333333", "email": "altifadev@gmail.com"}',
    'email',
    now(),
    now()
) ON CONFLICT (provider_id, provider) DO NOTHING;

-- Seed Merchant User
INSERT INTO public.merchant_users (
    id,
    merchant_id,
    first_name,
    last_name,
    role,
    created_at
) VALUES (
    '33333333-3333-3333-3333-333333333333',
    '163350b0-056d-4d5e-b5d4-24e7aac5ab6d',
    'Altifa',
    'Dev',
    'owner',
    now()
) ON CONFLICT (id) DO NOTHING;
