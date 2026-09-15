-- table_layout_presets was created with RLS for anon but never granted table
-- privileges (auto_expose_new_tables = false). Merchant JWT uses role `anon`,
-- so GET/POST failed with HTTP 401 / 42501 and painted iPad sync as failed.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.table_layout_presets TO anon, authenticated;

-- expenses often ships in the same missing-sync migration — grant if present.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'expenses'
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON public.expenses TO anon, authenticated';
    END IF;
END $$;
