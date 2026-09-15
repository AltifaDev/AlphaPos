-- Expense accounting treatment, fixed-asset schedule and investment analytics.
ALTER TABLE public.expenses
    ADD COLUMN IF NOT EXISTS recognition_type TEXT NOT NULL DEFAULT 'operating_expense',
    ADD COLUMN IF NOT EXISTS expense_nature TEXT NOT NULL DEFAULT 'other',
    ADD COLUMN IF NOT EXISTS is_vat_recoverable BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS recurrence_frequency TEXT NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS service_start_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS service_end_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS asset_class TEXT,
    ADD COLUMN IF NOT EXISTS available_for_use_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS useful_life_months INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS residual_value NUMERIC NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS investment_project TEXT,
    ADD COLUMN IF NOT EXISTS expected_monthly_cash_benefit NUMERIC NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS expected_monthly_incremental_cost NUMERIC NOT NULL DEFAULT 0;

UPDATE public.expenses
SET recognition_type = CASE WHEN is_capex THEN 'fixed_asset' ELSE 'operating_expense' END
WHERE recognition_type = 'operating_expense' AND is_capex = TRUE;

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_recognition_type_check;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_recognition_type_check
    CHECK (recognition_type IN ('operating_expense', 'fixed_asset', 'prepaid_expense', 'refundable_deposit'));

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_recurrence_frequency_check;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_recurrence_frequency_check
    CHECK (recurrence_frequency IN ('none', 'monthly', 'quarterly', 'yearly'));

CREATE INDEX IF NOT EXISTS idx_expenses_recognition
    ON public.expenses (merchant_id, recognition_type, date);
CREATE INDEX IF NOT EXISTS idx_expenses_investment_project
    ON public.expenses (merchant_id, investment_project) WHERE investment_project IS NOT NULL;
