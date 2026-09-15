-- Manager override flags for manual cash-drawer open (No-Sale) and drawer hardware tests.
ALTER TABLE public.security_policies
    ADD COLUMN IF NOT EXISTS require_manager_override_for_no_sale BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.security_policies
    ADD COLUMN IF NOT EXISTS require_manager_override_for_drawer_test BOOLEAN NOT NULL DEFAULT TRUE;
