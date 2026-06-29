-- Make the order webhook portable between Local Docker and hosted Supabase.
-- Provision these Vault secrets through scripts/supabase-local.sh configure:
--   service_role_key, edge_function_base_url

CREATE OR REPLACE FUNCTION public.trg_send_order_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
    v_base_url TEXT;
    v_service_key TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
        RAISE WARNING 'send-order-push skipped: pg_net is not installed';
        RETURN NEW;
    END IF;

    SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key'
    LIMIT 1;

    SELECT decrypted_secret INTO v_base_url
    FROM vault.decrypted_secrets
    WHERE name = 'edge_function_base_url'
    LIMIT 1;

    IF NULLIF(v_service_key, '') IS NULL OR NULLIF(v_base_url, '') IS NULL THEN
        RAISE WARNING 'send-order-push skipped: Vault secrets are not configured';
        RETURN NEW;
    END IF;

    PERFORM net.http_post(
        url := rtrim(v_base_url, '/') || '/functions/v1/send-order-push',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key,
            'apikey', v_service_key
        ),
        body := jsonb_build_object('order_id', NEW.id),
        timeout_milliseconds := 5000
    );

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- A notification outage must never roll back a paid/customer order.
    RAISE WARNING 'send-order-push failed: %', SQLERRM;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_send_order_push() FROM PUBLIC;
