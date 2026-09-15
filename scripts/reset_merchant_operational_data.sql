-- Production cutover reset for one merchant.
--
-- Usage:
--   1. Back up first.
--   2. Review counts:
--      psql "$DATABASE_URL" -v merchant_id='00000000-0000-0000-0000-000000000000' -f scripts/merchant_data_counts.sql
--   3. Reset operational data:
--      psql "$DATABASE_URL" -v merchant_id='00000000-0000-0000-0000-000000000000' -f scripts/reset_merchant_operational_data.sql
--
-- Preserves:
--   - public.merchants
--   - public.merchant_users
--   - public.audit_logs and public.audit_logs_archive
--
-- Everything else scoped by merchant_id is either soft-deleted when the table
-- supports is_deleted, or hard-deleted for join/queue/cache tables without an
-- is_deleted column.

\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE _reset_scope(merchant_id uuid) ON COMMIT DROP;
INSERT INTO _reset_scope VALUES (:'merchant_id');

CREATE TEMP TABLE _reset_report(
    table_name text,
    action text,
    affected_rows bigint
) ON COMMIT DROP;

DO $$
DECLARE
    target_merchant uuid := (SELECT merchant_id FROM _reset_scope LIMIT 1);
    table_record record;
    affected bigint;
    has_is_deleted boolean;
    has_updated_at boolean;
BEGIN
    IF target_merchant IS NULL THEN
        RAISE EXCEPTION 'merchant_id is required';
    END IF;

    -- Close active sessions first so realtime/table status guards settle cleanly.
    UPDATE public.table_sessions
    SET is_active = 0,
        ended_at = COALESCE(ended_at, now())
    WHERE merchant_id = target_merchant
      AND is_active = 1;
    GET DIAGNOSTICS affected = ROW_COUNT;
    INSERT INTO _reset_report VALUES ('table_sessions', 'close_active_sessions', affected);

    FOR table_record IN
        SELECT DISTINCT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'merchant_id'
          AND table_name NOT IN (
              'merchants',
              'merchant_users',
              'audit_logs',
              'audit_logs_archive'
          )
        ORDER BY table_name
    LOOP
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = table_record.table_name
              AND column_name = 'is_deleted'
        ) INTO has_is_deleted;

        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = table_record.table_name
              AND column_name = 'updated_at'
        ) INTO has_updated_at;

        IF has_is_deleted THEN
            IF has_updated_at THEN
                EXECUTE format(
                    'UPDATE public.%I SET is_deleted = true, updated_at = now() WHERE merchant_id = $1 AND COALESCE(is_deleted, false) = false',
                    table_record.table_name
                )
                USING target_merchant;
            ELSE
                EXECUTE format(
                    'UPDATE public.%I SET is_deleted = true WHERE merchant_id = $1 AND COALESCE(is_deleted, false) = false',
                    table_record.table_name
                )
                USING target_merchant;
            END IF;
            GET DIAGNOSTICS affected = ROW_COUNT;
            INSERT INTO _reset_report VALUES (table_record.table_name, 'soft_delete', affected);
        ELSE
            EXECUTE format('DELETE FROM public.%I WHERE merchant_id = $1', table_record.table_name)
            USING target_merchant;
            GET DIAGNOSTICS affected = ROW_COUNT;
            INSERT INTO _reset_report VALUES (table_record.table_name, 'delete', affected);
        END IF;
    END LOOP;
END;
$$;

SELECT table_name, action, affected_rows
FROM _reset_report
WHERE affected_rows > 0
ORDER BY table_name, action;

COMMIT;
