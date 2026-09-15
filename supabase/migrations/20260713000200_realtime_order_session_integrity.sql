-- Keep the always-on POS synchronized and reject customer orders for closed tables.

DO $$
DECLARE
    v_table_name TEXT;
BEGIN
    FOREACH v_table_name IN ARRAY ARRAY[
        'orders', 'order_items', 'table_sessions', 'restaurant_tables',
        'service_requests', 'payments'
    ]
    LOOP
        IF to_regclass('public.' || v_table_name) IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM pg_publication_tables
               WHERE pubname = 'supabase_realtime'
                 AND schemaname = 'public'
                 AND tablename = v_table_name
           ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table_name);
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_web_order_active_session()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.order_source = 'web' AND NOT EXISTS (
        SELECT 1
        FROM public.table_sessions session
        WHERE session.merchant_id = NEW.merchant_id
          AND session.table_number = NEW.table_number
          AND session.session_token = NEW.session_token
          AND session.is_active = 1
    ) THEN
        RAISE EXCEPTION 'web order requires an active table session'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_web_order_active_session ON public.orders;
CREATE TRIGGER trg_web_order_active_session
    BEFORE INSERT OR UPDATE OF merchant_id, table_number, session_token, order_source
    ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_web_order_active_session();
