-- Staff's whole-order serve/complete actions must update the header and its
-- active lines in one transaction, with an explicit observed order revision.
BEGIN;

CREATE FUNCTION public.transition_order_with_items(
    p_order_id uuid,
    p_branch_id uuid,
    p_expected_row_version bigint,
    p_status text,
    p_receipt_number text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_claims jsonb := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
    v_merchant_id uuid := NULLIF(v_claims->>'merchant_id', '')::uuid;
    v_branch_id uuid := NULLIF(v_claims->>'branch_id', '')::uuid;
    v_order public.orders%ROWTYPE;
    v_new_version bigint;
BEGIN
    IF v_merchant_id IS NULL OR v_branch_id IS DISTINCT FROM p_branch_id
       OR p_expected_row_version IS NULL OR p_expected_row_version < 1
       OR p_status IS NULL OR p_status NOT IN ('served', 'completed') THEN
        RAISE EXCEPTION 'invalid_order_transition' USING ERRCODE = '22023';
    END IF;
    PERFORM set_config('lock_timeout', '2000ms', true);

    SELECT * INTO v_order FROM public.orders
    WHERE id = p_order_id AND merchant_id = v_merchant_id
      AND branch_id = p_branch_id
    FOR UPDATE NOWAIT;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'order_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_order.row_version <> p_expected_row_version THEN
        RAISE EXCEPTION 'order_conflict id=% expected=% actual=%',
            p_order_id, p_expected_row_version, v_order.row_version
            USING ERRCODE = '40001';
    END IF;
    IF v_order.status IN ('cancelled', 'completed') AND v_order.status <> p_status THEN
        RAISE EXCEPTION 'terminal_order_cannot_transition' USING ERRCODE = '22023';
    END IF;

    IF v_order.status = p_status
       AND (p_receipt_number IS NULL OR btrim(p_receipt_number) = ''
            OR v_order.receipt_number = p_receipt_number)
       AND NOT EXISTS (
           SELECT 1 FROM public.order_items oi
           WHERE oi.order_id = p_order_id AND oi.merchant_id = v_merchant_id
             AND oi.branch_id = p_branch_id
             AND COALESCE(oi.is_deleted, false) = false
             AND oi.status NOT IN ('served', 'cancelled')
       ) THEN
        RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status,
                                  'order_row_version', v_order.row_version);
    END IF;

    UPDATE public.order_items
       SET status = 'served'
     WHERE order_id = p_order_id
       AND merchant_id = v_merchant_id
       AND branch_id = p_branch_id
       AND COALESCE(is_deleted, false) = false
       AND status NOT IN ('served', 'cancelled');

    UPDATE public.orders
       SET status = p_status,
           receipt_number = CASE
               WHEN p_receipt_number IS NULL OR btrim(p_receipt_number) = ''
               THEN receipt_number ELSE p_receipt_number END
     WHERE id = p_order_id AND merchant_id = v_merchant_id
       AND branch_id = p_branch_id
     RETURNING row_version INTO v_new_version;

    RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status,
                              'order_row_version', v_new_version);
END;
$$;

REVOKE ALL ON FUNCTION public.transition_order_with_items(uuid,uuid,bigint,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_order_with_items(uuid,uuid,bigint,text,text)
    TO anon, authenticated, service_role;

COMMIT;
