-- Usage:
--   psql "$DATABASE_URL" -v merchant_id='00000000-0000-0000-0000-000000000000' -f scripts/merchant_data_counts.sql
--
-- Shows row counts for every public table scoped by merchant_id.

\set ON_ERROR_STOP on

CREATE TEMP TABLE _reset_scope(merchant_id uuid);
INSERT INTO _reset_scope VALUES (:'merchant_id');

CREATE TEMP TABLE _merchant_data_counts(
    table_name text,
    row_count bigint
);

DO $$
DECLARE
    target_merchant uuid := (SELECT merchant_id FROM _reset_scope LIMIT 1);
    table_record record;
    table_count bigint;
BEGIN
    FOR table_record IN
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'merchant_id'
        ORDER BY table_name
    LOOP
        EXECUTE format('SELECT count(*) FROM public.%I WHERE merchant_id = $1', table_record.table_name)
        INTO table_count
        USING target_merchant;

        INSERT INTO _merchant_data_counts(table_name, row_count)
        VALUES (table_record.table_name, table_count);
    END LOOP;
END;
$$;

SELECT table_name, row_count
FROM _merchant_data_counts
WHERE row_count > 0
ORDER BY row_count DESC, table_name;
