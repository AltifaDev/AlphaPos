-- ============================================================
-- Migration: Staff Push Notification Triggers
-- Version: 20260711000400
-- Description: Database triggers that call send-staff-push
--              Edge Function automatically on key events.
--
-- Triggers created:
--   1. trg_push_new_order        → orders INSERT (status preparing/pending)
--   2. trg_push_order_status     → orders UPDATE (status changes to ready/served/cancelled)
--   3. trg_push_web_order        → orders INSERT (order_source = 'web')
--   4. trg_push_service_request  → service_requests INSERT (status pending)
--   5. trg_push_table_occupied   → restaurant_tables UPDATE (status → occupied)
--   6. trg_push_table_vacant     → restaurant_tables UPDATE (status → vacant)
--
-- Requires:
--   • pg_net extension (for async HTTP)
--   • supabase_functions schema accessible
-- ============================================================

-- ── Enable pg_net if not already enabled ────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS private;

-- ── Helper: build Edge Function URL ─────────────────────────
CREATE OR REPLACE FUNCTION private.staff_push_url()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT rtrim(decrypted_secret, '/') || '/functions/v1/send-staff-push'
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_base_url'
  LIMIT 1;
$$;

-- ── Helper: get service role key ────────────────────────────
CREATE OR REPLACE FUNCTION private.service_role_key()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT decrypted_secret
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;
$$;

-- ── Helper: generic push caller (async via pg_net) ───────────
-- Returns void — fire-and-forget. Does NOT block the triggering transaction.
CREATE OR REPLACE FUNCTION private.call_staff_push(payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url    text := private.staff_push_url();
  v_key    text := private.service_role_key();
  v_headers jsonb;
BEGIN
  -- Build auth header; if service_role_key is not available skip push
  -- (avoids crashing migrations in dev environments without secrets)
  IF v_key IS NULL OR v_key = '' THEN
    RETURN;
  END IF;

  v_headers := jsonb_build_object(
    'Content-Type',  'application/json',
    'Authorization', 'Bearer ' || v_key,
    'apikey',        v_key
  );

  -- Async HTTP POST — does not block the caller
  PERFORM net.http_post(
    url                  := v_url,
    body                 := payload,
    headers              := v_headers,
    timeout_milliseconds := 5000
  );

EXCEPTION WHEN OTHERS THEN
  -- Never fail the triggering transaction due to push errors
  RAISE WARNING 'staff_push: HTTP call failed: %', SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 1: New Order (INSERT, status = preparing or pending)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only fire for POS orders (not web orders — handled by separate trigger)
  IF NEW.status IN ('preparing', 'pending')
     AND (NEW.order_source IS DISTINCT FROM 'web') THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   'new_order',
      'merchant_id',  NEW.merchant_id::text,
      'order_id',     NEW.id::text,
      'order_number', NEW.order_number::text,
      'table_number', NEW.table_number
    ));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_new_order ON public.orders;
CREATE TRIGGER trg_push_new_order
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_new_order();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 2: Order Status Change (UPDATE → ready / served / cancelled)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_order_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_event text;
BEGIN
  -- Only fire when status actually changes
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  CASE NEW.status
    WHEN 'ready'     THEN v_event := 'order_ready';
    WHEN 'served'    THEN v_event := 'order_served';
    WHEN 'cancelled' THEN v_event := 'order_cancelled';
    ELSE v_event := NULL;
  END CASE;

  IF v_event IS NOT NULL THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   v_event,
      'merchant_id',  NEW.merchant_id::text,
      'order_id',     NEW.id::text,
      'order_number', NEW.order_number::text,
      'table_number', NEW.table_number
    ));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_order_status ON public.orders;
CREATE TRIGGER trg_push_order_status
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_order_status();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 3: Web Order (INSERT, order_source = 'web')
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_web_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.order_source = 'web' AND NEW.status IN ('pending', 'preparing') THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   'web_order',
      'merchant_id',  NEW.merchant_id::text,
      'order_id',     NEW.id::text,
      'order_number', NEW.order_number::text,
      'table_number', NEW.table_number,
      'message',      'New web order received — send to kitchen'
    ));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_web_order ON public.orders;
CREATE TRIGGER trg_push_web_order
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_web_order();

-- Replaced by the source-aware triggers above. Keeping both would send duplicates.
DROP TRIGGER IF EXISTS trg_order_insert_push ON public.orders;

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 4: Service Request (INSERT, status = pending)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_service_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.status = 'pending' THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   'service_request',
      'merchant_id',  NEW.merchant_id::text,
      'request_id',   NEW.id::text,
      'table_number', NEW.table_number,
      'request_type', NEW.request_type
    ));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_service_request ON public.service_requests;
CREATE TRIGGER trg_push_service_request
  AFTER INSERT ON public.service_requests
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_service_request();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 5 & 6: Table Status Changes (occupied / vacant)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_table_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_event text;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'occupied' THEN
    v_event := 'table_occupied';
  ELSIF NEW.status = 'vacant' AND OLD.status = 'occupied' THEN
    v_event := 'table_vacant';
  ELSE
    RETURN NEW;
  END IF;

  PERFORM private.call_staff_push(jsonb_build_object(
    'event_type',   v_event,
    'merchant_id',  NEW.merchant_id::text,
    'table_number', NEW.table_number
  ));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_table_status ON public.restaurant_tables;
CREATE TRIGGER trg_push_table_status
  AFTER UPDATE OF status ON public.restaurant_tables
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_table_status();

-- ─────────────────────────────────────────────────────────────
-- Ensure employee_id column exists in push_devices
-- (needed for targeted shift/timecard notifications)
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'push_devices'
      AND column_name  = 'employee_id'
  ) THEN
    ALTER TABLE public.push_devices
      ADD COLUMN employee_id uuid REFERENCES public.employees(id) ON DELETE SET NULL;
    COMMENT ON COLUMN public.push_devices.employee_id IS
      'Logged-in employee who owns this device session. NULL means any staff member.';
  END IF;
END;
$$;

-- Index for employee-targeted pushes
CREATE INDEX IF NOT EXISTS idx_push_devices_employee_id
  ON public.push_devices(employee_id)
  WHERE employee_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- Grant execute on helper functions to service_role
-- ─────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION private.call_staff_push(jsonb)      TO service_role;
GRANT EXECUTE ON FUNCTION private.staff_push_url()             TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_new_order()      TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_order_status()   TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_web_order()      TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_service_request() TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_table_status()   TO service_role;
