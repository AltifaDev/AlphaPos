-- Keep customer-web orders in the status contract used by POS/Staff alerts.
-- Older cached web clients may still submit `pending`; normalize them before
-- realtime subscribers and order push webhooks see the row.

CREATE OR REPLACE FUNCTION public.trg_normalize_web_order_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'pending' AND NULLIF(NEW.session_token, '') IS NOT NULL THEN
        NEW.status := 'preparing';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_web_order_status ON public.orders;
CREATE TRIGGER trg_normalize_web_order_status
    BEFORE INSERT OR UPDATE OF status ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_normalize_web_order_status();
