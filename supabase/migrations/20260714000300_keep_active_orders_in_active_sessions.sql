-- An open order and a closed table session describe mutually exclusive table
-- states. Repair existing rows, then reject future attempts to close a session
-- before its orders reach a terminal status.

WITH latest_open_order AS (
    SELECT DISTINCT ON (merchant_id, table_number)
        merchant_id,
        table_number,
        session_token,
        GREATEST(1, COALESCE(guest_count, 1)) AS guest_count,
        created_at
    FROM public.orders
    WHERE COALESCE(is_deleted, false) = false
      AND status IN ('pending', 'preparing', 'ready')
      AND NULLIF(session_token, '') IS NOT NULL
    ORDER BY merchant_id, table_number, created_at DESC
)
UPDATE public.table_sessions session
SET is_active = 1,
    ended_at = NULL,
    guest_count = open_order.guest_count
FROM latest_open_order open_order
WHERE session.merchant_id = open_order.merchant_id
  AND session.session_token = open_order.session_token
  AND session.is_active <> 1
  AND NOT EXISTS (
      SELECT 1
      FROM public.table_sessions active_session
      WHERE active_session.merchant_id = open_order.merchant_id
        AND active_session.table_number = open_order.table_number
        AND active_session.is_active = 1
  );

INSERT INTO public.table_sessions (
    id, merchant_id, table_number, session_token, is_active, guest_count, created_at
)
WITH latest_open_order AS (
    SELECT DISTINCT ON (merchant_id, table_number)
        merchant_id,
        table_number,
        session_token,
        GREATEST(1, COALESCE(guest_count, 1)) AS guest_count,
        created_at
    FROM public.orders
    WHERE COALESCE(is_deleted, false) = false
      AND status IN ('pending', 'preparing', 'ready')
      AND NULLIF(session_token, '') IS NOT NULL
    ORDER BY merchant_id, table_number, created_at DESC
)
SELECT
    gen_random_uuid(), merchant_id, table_number, session_token, 1, guest_count, created_at
FROM latest_open_order open_order
WHERE NOT EXISTS (
    SELECT 1
    FROM public.table_sessions session
    WHERE session.merchant_id = open_order.merchant_id
      AND session.session_token = open_order.session_token
)
  AND NOT EXISTS (
      SELECT 1
      FROM public.table_sessions active_session
      WHERE active_session.merchant_id = open_order.merchant_id
        AND active_session.table_number = open_order.table_number
        AND active_session.is_active = 1
  );

CREATE OR REPLACE FUNCTION public.guard_active_orders_on_session_close()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF OLD.is_active = 1
       AND COALESCE(NEW.is_active, 0) <> 1
       AND EXISTS (
           SELECT 1
           FROM public.orders
           WHERE merchant_id = OLD.merchant_id
             AND session_token = OLD.session_token
             AND COALESCE(is_deleted, false) = false
             AND status IN ('pending', 'preparing', 'ready')
       ) THEN
        RAISE EXCEPTION 'cannot close a session with open orders'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_active_orders_on_session_close ON public.table_sessions;
CREATE TRIGGER trg_guard_active_orders_on_session_close
    BEFORE UPDATE OF is_active ON public.table_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_active_orders_on_session_close();
