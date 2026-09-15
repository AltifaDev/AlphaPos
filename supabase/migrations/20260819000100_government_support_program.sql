BEGIN;

ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS support_program_name TEXT,
    ADD COLUMN IF NOT EXISTS support_government_rate NUMERIC(5,4) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS support_citizen_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS support_government_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS support_settlement_status TEXT NOT NULL DEFAULT 'not_applicable';

ALTER TABLE public.orders
    DROP CONSTRAINT IF EXISTS orders_support_government_rate_check,
    ADD CONSTRAINT orders_support_government_rate_check
        CHECK (support_government_rate BETWEEN 0 AND 1),
    DROP CONSTRAINT IF EXISTS orders_support_amounts_check,
    ADD CONSTRAINT orders_support_amounts_check
        CHECK (support_citizen_amount >= 0 AND support_government_amount >= 0),
    DROP CONSTRAINT IF EXISTS orders_support_settlement_status_check,
    ADD CONSTRAINT orders_support_settlement_status_check
        CHECK (support_settlement_status IN ('not_applicable', 'pending', 'received', 'rejected'));

CREATE INDEX IF NOT EXISTS idx_orders_support_reconciliation
    ON public.orders (merchant_id, support_program_name, support_settlement_status, created_at)
    WHERE support_program_name IS NOT NULL AND COALESCE(is_deleted, false) = false;

COMMENT ON COLUMN public.orders.support_government_amount IS
    'Government receivable portion; not customer payment and not delivery fee/GP';

COMMIT;
