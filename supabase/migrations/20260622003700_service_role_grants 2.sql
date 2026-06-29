-- Grant service_role read/write access to all public tables.
-- service_role bypasses RLS but still needs table-level GRANT when
-- auto_expose_new_tables = false (set in config.toml).
-- Edge Functions (issue-merchant-token, send-order-push, etc.) use the
-- service_role key and would receive "permission denied" without this.

GRANT USAGE ON SCHEMA public TO service_role;

-- Blanket grant on all current tables
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA public
    TO service_role;

-- Ensure future tables also get the grant
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO service_role;

-- Sequences (needed for INSERT with serial columns)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO service_role;
