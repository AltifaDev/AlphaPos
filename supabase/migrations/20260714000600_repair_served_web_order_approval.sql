-- Keep web-order approval and service states monotonic:
-- pending -> approved/cooking -> served, never served -> preparing.

UPDATE public.orders o
   SET status = 'served',
       is_staff_confirmed = TRUE,
       updated_at = now()
 WHERE o.order_source = 'web'
   AND o.is_staff_confirmed IS DISTINCT FROM TRUE
   AND o.is_deleted = FALSE
   AND EXISTS (
       SELECT 1 FROM public.order_items oi
        WHERE oi.order_id = o.id AND oi.is_deleted = FALSE
   )
   AND NOT EXISTS (
       SELECT 1 FROM public.order_items oi
        WHERE oi.order_id = o.id
          AND oi.is_deleted = FALSE
          AND oi.status NOT IN ('served', 'cancelled')
   );

CREATE OR REPLACE FUNCTION public.approve_customer_order(p_order_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID := public.get_active_merchant_id();
BEGIN
    IF v_merchant_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.orders
         WHERE id = p_order_id
           AND merchant_id = v_merchant_id
           AND order_source = 'web'
           AND is_deleted = FALSE
    ) THEN
        RAISE EXCEPTION 'customer order not found for active merchant';
    END IF;

    -- Historical clients could serve every line before approval. Normalize the
    -- header without moving the completed service workflow backwards.
    IF EXISTS (
        SELECT 1 FROM public.order_items
         WHERE order_id = p_order_id AND merchant_id = v_merchant_id AND is_deleted = FALSE
    ) AND NOT EXISTS (
        SELECT 1 FROM public.order_items
         WHERE order_id = p_order_id
           AND merchant_id = v_merchant_id
           AND is_deleted = FALSE
           AND status NOT IN ('served', 'cancelled')
    ) THEN
        UPDATE public.orders
           SET status = 'served', is_staff_confirmed = TRUE, updated_at = now()
         WHERE id = p_order_id AND merchant_id = v_merchant_id;
        RETURN p_order_id;
    END IF;

    UPDATE public.orders
       SET status = 'preparing', is_staff_confirmed = TRUE, updated_at = now()
     WHERE id = p_order_id AND merchant_id = v_merchant_id;

    UPDATE public.order_items
       SET status = 'cooking', updated_at = now()
     WHERE order_id = p_order_id
       AND merchant_id = v_merchant_id
       AND status = 'pending'
       AND is_deleted = FALSE;

    RETURN p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_customer_order(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_customer_order(UUID) TO anon, authenticated;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM public.orders o
         WHERE o.order_source = 'web'
           AND o.is_staff_confirmed IS DISTINCT FROM TRUE
           AND o.is_deleted = FALSE
           AND EXISTS (SELECT 1 FROM public.order_items oi WHERE oi.order_id = o.id AND oi.is_deleted = FALSE)
           AND NOT EXISTS (
               SELECT 1 FROM public.order_items oi
                WHERE oi.order_id = o.id AND oi.is_deleted = FALSE
                  AND oi.status NOT IN ('served', 'cancelled')
           )
    ) THEN
        RAISE EXCEPTION 'served web-order approval repair failed';
    END IF;
END;
$$;
