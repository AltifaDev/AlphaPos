-- Paid Quick Orders created by AlphaPosStaff must remain actionable on KDS.
-- Payment settlement is financial; it must not mark food as served.
-- Every other checkout path keeps the existing serve-before-payment behavior.

CREATE OR REPLACE FUNCTION public.complete_checkout_atomic(
    p_order_id UUID,
    p_idempotency_key TEXT,
    p_payments JSONB,
    p_table_number TEXT DEFAULT 'QUICK',
    p_breakdown JSONB DEFAULT '{}'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
    v_existing public.checkout_operations%ROWTYPE;
    v_payment JSONB;
    v_total NUMERIC := 0;
    v_response JSONB;
    v_branch UUID := public.get_active_branch_id();
    v_kitchen_required BOOLEAN := TRUE;
    v_table_status TEXT := 'cleaning';
    v_is_staff_quick BOOLEAN := FALSE;
BEGIN
    IF NULLIF(trim(p_idempotency_key), '') IS NULL OR jsonb_array_length(COALESCE(p_payments, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'invalid_checkout_request';
    END IF;

    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND OR v_order.merchant_id IS DISTINCT FROM public.get_active_merchant_id() THEN RAISE EXCEPTION 'order_not_found'; END IF;
    IF v_branch IS NOT NULL AND v_order.branch_id IS DISTINCT FROM v_branch THEN RAISE EXCEPTION 'branch_mismatch'; END IF;

    v_is_staff_quick := lower(COALESCE(v_order.order_source, '')) = 'staff'
        AND upper(COALESCE(v_order.table_number, p_table_number, '')) = 'QUICK'
        AND lower(COALESCE(v_order.order_type, '')) IN ('take_out', 'takeaway', 'walk_in', 'delivery');

    SELECT COALESCE(kitchen_workflow_required, TRUE) INTO v_kitchen_required
      FROM public.merchants WHERE id = v_order.merchant_id;

    -- Staff Quick Orders are payment-first. All other clients retain the
    -- existing serve-before-payment policy without any behavior change.
    IF NOT v_is_staff_quick AND v_kitchen_required AND EXISTS (
        SELECT 1 FROM public.order_items
        WHERE order_id = p_order_id AND NOT COALESCE(is_deleted, FALSE)
          AND status IN ('pending','cooking','alert','preparing','ready')
    ) THEN
        RAISE EXCEPTION 'kitchen_service_required';
    END IF;

    SELECT * INTO v_existing FROM public.checkout_operations
      WHERE merchant_id = v_order.merchant_id AND idempotency_key = p_idempotency_key;
    IF FOUND AND v_existing.state = 'completed' THEN RETURN v_existing.response; END IF;

    INSERT INTO public.checkout_operations(merchant_id, branch_id, order_id, idempotency_key, state, request)
    VALUES(v_order.merchant_id, v_order.branch_id, p_order_id, p_idempotency_key, 'processing',
           jsonb_build_object('payments', p_payments, 'breakdown', p_breakdown))
    ON CONFLICT (merchant_id, idempotency_key) DO UPDATE SET state='processing', updated_at=now();

    FOR v_payment IN SELECT value FROM jsonb_array_elements(p_payments) LOOP
        IF COALESCE((v_payment->>'amount')::numeric, 0) <= 0 THEN RAISE EXCEPTION 'invalid_payment_amount'; END IF;
        INSERT INTO public.payments(id, merchant_id, branch_id, order_id, amount, payment_method, status, created_at, idempotency_key)
        VALUES((v_payment->>'id')::uuid, v_order.merchant_id, v_order.branch_id, p_order_id,
               (v_payment->>'amount')::numeric, v_payment->>'payment_method', 'completed', now(),
               p_idempotency_key || ':' || (v_payment->>'id'))
        ON CONFLICT (id) DO NOTHING;
        v_total := v_total + (v_payment->>'amount')::numeric;
    END LOOP;

    IF abs(v_total - COALESCE((p_breakdown->>'grand_total')::numeric, v_order.total)) > 0.05 THEN
        RAISE EXCEPTION 'payment_total_mismatch';
    END IF;

    UPDATE public.orders SET status='completed',
      subtotal=COALESCE((p_breakdown->>'subtotal')::numeric, NULLIF(subtotal,0), total),
      tax=COALESCE((p_breakdown->>'tax')::numeric,tax),
      service_charge=COALESCE((p_breakdown->>'service_charge')::numeric,service_charge),
      discount=COALESCE((p_breakdown->>'discount')::numeric,discount),
      total=v_total, updated_at=now() WHERE id=p_order_id;

    -- Critical distinction: paid Staff Quick food stays cooking for KDS.
    IF NOT v_is_staff_quick THEN
        UPDATE public.order_items SET status='served'
        WHERE order_id=p_order_id AND status <> 'cancelled';
    END IF;

    v_table_status := COALESCE(NULLIF(p_breakdown->>'table_status_after_checkout', ''), 'cleaning');
    IF v_table_status NOT IN ('cleaning', 'vacant') THEN RAISE EXCEPTION 'invalid_table_status_after_checkout'; END IF;
    IF upper(COALESCE(p_table_number,'QUICK')) <> 'QUICK' THEN
      UPDATE public.table_sessions SET is_active=0, ended_at=now()
      WHERE merchant_id=v_order.merchant_id AND branch_id IS NOT DISTINCT FROM v_order.branch_id
        AND table_number=p_table_number AND is_active=1;
      UPDATE public.restaurant_tables SET status=v_table_status, updated_at=now()
      WHERE merchant_id=v_order.merchant_id AND branch_id IS NOT DISTINCT FROM v_order.branch_id
        AND table_number=p_table_number;
    END IF;

    v_response := jsonb_build_object('status','completed','order_id',p_order_id,'amount',v_total,
      'idempotency_key',p_idempotency_key,'table_status',v_table_status);
    UPDATE public.checkout_operations SET state='completed', response=v_response, updated_at=now()
    WHERE merchant_id=v_order.merchant_id AND idempotency_key=p_idempotency_key;
    RETURN v_response;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_checkout_atomic(UUID,TEXT,JSONB,TEXT,JSONB) TO anon, authenticated;
