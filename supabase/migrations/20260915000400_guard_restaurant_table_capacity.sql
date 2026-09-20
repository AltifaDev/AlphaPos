-- Enforce the active-table ceiling at the source of truth. The client also
-- validates this for UX, but concurrent/offline devices must not be able to
-- race past the limit. This trigger rejects writes; it never deletes rows.

CREATE OR REPLACE FUNCTION public.guard_restaurant_table_capacity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_active_count integer;
BEGIN
    IF COALESCE(NEW.is_deleted, false) THEN
        RETURN NEW;
    END IF;

    -- Serialize capacity decisions for one merchant branch while allowing
    -- unrelated tenants/branches to proceed independently.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(NEW.merchant_id::text || ':' || NEW.branch_id::text, 0)
    );

    SELECT count(*)
      INTO v_active_count
      FROM public.restaurant_tables AS rt
     WHERE rt.merchant_id = NEW.merchant_id
       AND rt.branch_id = NEW.branch_id
       AND NOT rt.is_deleted
       AND rt.id <> NEW.id;

    IF v_active_count >= 80 THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'restaurant_table_limit_exceeded',
            DETAIL = format(
                'Merchant %s branch %s already has %s active tables',
                NEW.merchant_id,
                NEW.branch_id,
                v_active_count
            );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_restaurant_table_capacity
    ON public.restaurant_tables;

CREATE TRIGGER trg_guard_restaurant_table_capacity
BEFORE INSERT OR UPDATE OF is_deleted, merchant_id, branch_id
ON public.restaurant_tables
FOR EACH ROW
EXECUTE FUNCTION public.guard_restaurant_table_capacity();

