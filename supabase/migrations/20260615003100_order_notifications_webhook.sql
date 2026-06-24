-- Migration: 028_order_notifications_webhook.sql
-- Description: Server-side push notification trigger on new orders via Edge Function.

CREATE OR REPLACE FUNCTION public.trg_send_order_push()
RETURNS TRIGGER AS $$
DECLARE
    v_url TEXT;
    v_service_key TEXT;
BEGIN
    -- Only trigger if the pg_net extension exists (standard in Supabase)
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
        
        -- Retrieve service role key from the vault if available (hosted/secure dev)
        BEGIN
            SELECT decrypted_secret INTO v_service_key 
            FROM vault.decrypted_secrets 
            WHERE name = 'service_role_key' 
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_service_key := NULL;
        END;

        -- Local Kong container proxy URL is standard for internal calls
        v_url := 'http://kong:8000/functions/v1/send-order-push';

        -- Fire the HTTP request asynchronously to avoid blocking the insert transaction
        PERFORM net.http_post(
            url := v_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || COALESCE(v_service_key, '')
            ),
            body := jsonb_build_object('order_id', NEW.id),
            timeout_milliseconds := 5000
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger on public.orders
DROP TRIGGER IF EXISTS trg_order_insert_push ON public.orders;
CREATE TRIGGER trg_order_insert_push
    AFTER INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_send_order_push();
