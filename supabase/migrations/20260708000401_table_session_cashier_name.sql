-- Store the cashier who opened the table session so POS headers stay correct
-- across devices and offline/online sync.

ALTER TABLE public.table_sessions
    ADD COLUMN IF NOT EXISTS cashier_name VARCHAR(100);

COMMENT ON COLUMN public.table_sessions.cashier_name IS
    'Display name of the staff member who opened or currently owns the table session.';
