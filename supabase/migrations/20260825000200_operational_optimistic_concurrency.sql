BEGIN;

-- Shared optimistic-concurrency token for entities that can be edited from
-- more than one POS/KDS terminal. Existing REST clients remain compatible;
-- conflict-aware clients PATCH with `row_version=eq.<last seen>`.
DO $migration$
DECLARE
  target text;
BEGIN
  FOREACH target IN ARRAY ARRAY[
    'orders', 'order_items', 'table_sessions', 'restaurant_tables',
    'purchase_orders', 'purchase_order_items', 'inventory_lots',
    'inventory_transactions', 'menu_items', 'customers'
  ] LOOP
    IF to_regclass('public.' || target) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)', target);
    END IF;
  END LOOP;
END $migration$;

CREATE OR REPLACE FUNCTION public.bump_operational_row_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- The server owns the token. A client cannot skip or forge a revision.
  NEW.row_version := OLD.row_version + 1;
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

DO $migration$
DECLARE
  target text;
BEGIN
  FOREACH target IN ARRAY ARRAY[
    'orders', 'order_items', 'table_sessions', 'restaurant_tables',
    'purchase_orders', 'purchase_order_items', 'inventory_lots',
    'inventory_transactions', 'menu_items', 'customers'
  ] LOOP
    IF to_regclass('public.' || target) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_%I_row_version ON public.%I', target, target);
      EXECUTE format(
        'CREATE TRIGGER trg_%I_row_version BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.bump_operational_row_version()',
        target, target
      );
    END IF;
  END LOOP;
END $migration$;

-- Conflicts are durable server-side as well as in each device journal. This is
-- intentionally append-only so a support audit survives device replacement.
CREATE TABLE IF NOT EXISTS public.sync_conflict_journal (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  device_id text,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  expected_version bigint,
  server_version bigint,
  local_updated_at timestamptz,
  server_updated_at timestamptz,
  resolution text NOT NULL CHECK (resolution IN ('server_won','local_retried','manual_required')),
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sync_conflict_journal_scope
ON public.sync_conflict_journal (merchant_id, branch_id, created_at DESC);

ALTER TABLE public.sync_conflict_journal ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS merchant_isolation_sync_conflict_journal ON public.sync_conflict_journal;
CREATE POLICY merchant_isolation_sync_conflict_journal ON public.sync_conflict_journal
FOR ALL USING (merchant_id = public.get_active_merchant_id())
WITH CHECK (merchant_id = public.get_active_merchant_id());

REVOKE UPDATE, DELETE, TRUNCATE ON public.sync_conflict_journal FROM anon, authenticated;
GRANT SELECT, INSERT ON public.sync_conflict_journal TO anon, authenticated, service_role;

COMMIT;
