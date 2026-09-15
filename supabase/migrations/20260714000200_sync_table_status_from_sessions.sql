-- Keep restaurant_tables in sync when a session changes. Without this, a
-- delayed `restaurant_tables` realtime event can overwrite the session-derived
-- status on another device and show the same table as vacant.

CREATE OR REPLACE FUNCTION public.sync_restaurant_table_status_from_sessions(
    p_merchant_id UUID,
    p_table_number TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_has_active_session BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM public.table_sessions
        WHERE merchant_id = p_merchant_id
          AND table_number = p_table_number
          AND is_active = 1
    ) INTO v_has_active_session;

    UPDATE public.restaurant_tables
    SET status = CASE WHEN v_has_active_session THEN 'occupied' ELSE 'vacant' END,
        updated_at = now()
    WHERE merchant_id = p_merchant_id
      AND table_number = p_table_number
      AND (
          (v_has_active_session AND status IS DISTINCT FROM 'occupied') OR
          (NOT v_has_active_session AND status = 'occupied')
      );
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_sync_table_status_from_sessions()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        PERFORM public.sync_restaurant_table_status_from_sessions(OLD.merchant_id, OLD.table_number);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM public.sync_restaurant_table_status_from_sessions(NEW.merchant_id, NEW.table_number);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- The VPS currently has two older triggers with overlapping writes. Remove
-- both so one session change produces exactly one table-status transition.
DROP TRIGGER IF EXISTS trg_sync_table_status ON public.table_sessions;
DROP TRIGGER IF EXISTS trg_sync_table_status_from_session ON public.table_sessions;
DROP TRIGGER IF EXISTS trg_sync_table_status_from_sessions ON public.table_sessions;
CREATE TRIGGER trg_sync_table_status_from_sessions
    AFTER INSERT OR UPDATE OR DELETE ON public.table_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_sync_table_status_from_sessions();

SELECT public.reconcile_restaurant_table_statuses();
