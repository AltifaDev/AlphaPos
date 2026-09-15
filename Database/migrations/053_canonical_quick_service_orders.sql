-- Canonical Quick Service order identity.
-- Apply the equivalent Supabase migration before enabling mixed POS modes.

CREATE OR REPLACE FUNCTION public.normalize_order_service_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    table_exists boolean;
BEGIN
    IF NEW.order_type IN ('take_out', 'delivery', 'walk_in') THEN
        NEW.table_number := 'QUICK';
        NEW.table_session_id := NULL;
        RETURN NEW;
    END IF;

    IF NEW.order_type = 'dine_in' THEN
        IF NEW.table_number IS NULL OR btrim(NEW.table_number) = '' OR upper(NEW.table_number) = 'QUICK' THEN
            RAISE EXCEPTION 'Dine-in orders require a real restaurant table';
        END IF;

        SELECT EXISTS (
            SELECT 1 FROM public.restaurant_tables t
            WHERE t.merchant_id = NEW.merchant_id
              AND (NEW.branch_id IS NULL OR t.branch_id = NEW.branch_id)
              AND t.table_number = NEW.table_number
              AND COALESCE(t.is_deleted, false) = false
        ) INTO table_exists;

        IF NOT table_exists THEN
            RAISE EXCEPTION 'Unknown restaurant table: %', NEW.table_number;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_order_service_identity ON public.orders;
CREATE TRIGGER trg_normalize_order_service_identity
BEFORE INSERT OR UPDATE OF order_type, table_number, table_session_id, merchant_id, branch_id
ON public.orders FOR EACH ROW
EXECUTE FUNCTION public.normalize_order_service_identity();
