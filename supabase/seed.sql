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

-- Seed Employees
INSERT INTO public.employees (id, merchant_id, first_name, last_name, phone, national_id, employment_type, pay_rate, username, pin_code, role)
VALUES 
(
    '11111111-1111-1111-1111-111111111111',
    '163350b0-056d-4d5e-b5d4-24e7aac5ab6d',
    'Somchai',
    'Suksabai',
    '081-234-5678',
    '1234567890123',
    'monthly',
    25000.00,
    'somchai',
    '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
    'Manager'
),
(
    '22222222-2222-2222-2222-222222222222',
    '163350b0-056d-4d5e-b5d4-24e7aac5ab6d',
    'Somsri',
    'Jaidee',
    '089-876-5432',
    '9876543210987',
    'hourly',
    75.00,
    'somsri',
    '3f786850e387550fdab836ed7e6dc881de23001bdec45830613a48e7347793d4',
    'Barista'
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

