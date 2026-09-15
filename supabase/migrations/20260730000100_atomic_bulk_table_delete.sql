CREATE OR REPLACE FUNCTION public.bulk_soft_delete_restaurant_tables(p_table_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
    v_deleted_count INTEGER;
BEGIN
    IF v_merchant_id IS NULL OR COALESCE(array_length(p_table_ids, 1), 0) = 0 THEN
        RETURN 0;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.table_sessions AS session
        WHERE session.merchant_id = v_merchant_id
          AND session.table_id = ANY(p_table_ids)
          AND session.is_active = 1
          AND COALESCE(session.is_deleted, FALSE) = FALSE
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'cannot delete tables with active sessions';
    END IF;

    UPDATE public.restaurant_tables
    SET is_deleted = TRUE,
        updated_at = clock_timestamp()
    WHERE merchant_id = v_merchant_id
      AND id = ANY(p_table_ids)
      AND is_deleted = FALSE;

    SELECT COUNT(*)
    INTO v_deleted_count
    FROM public.restaurant_tables
    WHERE merchant_id = v_merchant_id
      AND id = ANY(p_table_ids)
      AND is_deleted = TRUE;

    RETURN v_deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_soft_delete_restaurant_tables(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulk_soft_delete_restaurant_tables(UUID[]) TO anon, authenticated;
