-- =========================================================================
-- Migration: 20260916000800_comprehensive_idempotency_and_concurrency.sql
-- Description: Complete Idempotency across All Critical Operations &
--              Optimistic Concurrency (row_version) Expansion
-- Features:
--   1. Idempotency for transition_order_with_items (status transition replay)
--   2. Atomic idempotent cancel_order_atomic (void/cancel with reason)
--   3. Atomic idempotent refund_order_atomic (refund with idempotency)
--   4. Optimistic locking (row_version) on register_sessions, inventory_items, cash_movements
--   5. Automatic conflict logging into sync_conflict_journal on version mismatch
-- =========================================================================

BEGIN;

-- 1. Ensure row_version and bump trigger on missing operational tables
DO $$
DECLARE
  target text;
BEGIN
  FOREACH target IN ARRAY ARRAY[
    'register_sessions', 'inventory_items', 'cash_movements'
  ] LOOP
    IF to_regclass('public.' || target) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)', target);
      EXECUTE format('DROP TRIGGER IF EXISTS trg_%I_row_version ON public.%I', target, target);
      EXECUTE format(
        'CREATE TRIGGER trg_%I_row_version BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.bump_operational_row_version()',
        target, target
      );
    END IF;
  END LOOP;
END $$;

-- 2. Upgrade transition_order_with_items with operation_id idempotency
CREATE OR REPLACE FUNCTION public.transition_order_with_items(
    p_order_id UUID,
    p_branch_id UUID,
    p_expected_row_version BIGINT,
    p_status TEXT,
    p_receipt_number TEXT DEFAULT NULL,
    p_operation_id TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_claims JSONB := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
    v_merchant_id UUID := NULLIF(v_claims->>'merchant_id', '')::UUID;
    v_branch_id UUID := NULLIF(v_claims->>'branch_id', '')::UUID;
    v_order public.orders%ROWTYPE;
    v_new_version BIGINT;
    v_op_id TEXT := NULLIF(btrim(p_operation_id), '');
    v_previous_response JSONB;
    v_response JSONB;
    v_inserted INTEGER;
    v_req_snapshot JSONB;
BEGIN
    IF v_merchant_id IS NULL OR (v_branch_id IS NOT NULL AND v_branch_id IS DISTINCT FROM p_branch_id)
       OR p_expected_row_version IS NULL OR p_expected_row_version < 1
       OR p_status IS NULL OR p_status NOT IN ('served', 'completed') THEN
        RAISE EXCEPTION 'invalid_order_transition' USING ERRCODE = '22023';
    END IF;
    PERFORM set_config('lock_timeout', '2000ms', true);

    -- Idempotency check if operation_id is provided
    IF v_op_id IS NOT NULL THEN
        v_req_snapshot := jsonb_build_object(
            'action', 'transition',
            'order_id', p_order_id,
            'status', p_status,
            'expected_version', p_expected_row_version,
            'receipt_number', p_receipt_number
        );

        INSERT INTO public.order_mutation_operations
            (merchant_id, operation_id, order_id, request)
        VALUES (v_merchant_id, v_op_id, p_order_id, v_req_snapshot)
        ON CONFLICT (merchant_id, operation_id) DO NOTHING;
        GET DIAGNOSTICS v_inserted = ROW_COUNT;

        IF v_inserted = 0 THEN
            SELECT response INTO v_previous_response
              FROM public.order_mutation_operations
             WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;
            IF v_previous_response IS NOT NULL THEN
                RETURN v_previous_response;
            END IF;
        END IF;
    END IF;

    SELECT * INTO v_order FROM public.orders
    WHERE id = p_order_id AND merchant_id = v_merchant_id
      AND (p_branch_id IS NULL OR branch_id = p_branch_id)
    FOR UPDATE NOWAIT;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'order_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF v_order.row_version <> p_expected_row_version THEN
        -- Log conflict into sync_conflict_journal
        INSERT INTO public.sync_conflict_journal (
            merchant_id, branch_id, entity_type, entity_id,
            expected_version, server_version, resolution, details
        ) VALUES (
            v_merchant_id, v_order.branch_id, 'orders', p_order_id::text,
            p_expected_row_version, v_order.row_version, 'manual_required',
            jsonb_build_object('action', 'transition', 'attempted_status', p_status)
        );

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
             AND COALESCE(oi.is_deleted, false) = false
             AND oi.status NOT IN ('served', 'cancelled')
       ) THEN
        v_response := jsonb_build_object('order_id', p_order_id, 'status', p_status,
                                        'order_row_version', v_order.row_version);
        IF v_op_id IS NOT NULL THEN
            UPDATE public.order_mutation_operations SET response = v_response
            WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;
        END IF;
        RETURN v_response;
    END IF;

    UPDATE public.order_items
       SET status = 'served'
     WHERE order_id = p_order_id
       AND merchant_id = v_merchant_id
       AND COALESCE(is_deleted, false) = false
       AND status NOT IN ('served', 'cancelled');

    UPDATE public.orders
       SET status = p_status,
           receipt_number = CASE
               WHEN p_receipt_number IS NULL OR btrim(p_receipt_number) = ''
               THEN receipt_number ELSE p_receipt_number END
     WHERE id = p_order_id AND merchant_id = v_merchant_id
     RETURNING row_version INTO v_new_version;

    v_response := jsonb_build_object('order_id', p_order_id, 'status', p_status,
                                    'order_row_version', v_new_version);

    IF v_op_id IS NOT NULL THEN
        UPDATE public.order_mutation_operations SET response = v_response
        WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;
    END IF;

    RETURN v_response;
END;
$$;

-- 3. Atomic Idempotent Order Cancellation / Void
CREATE OR REPLACE FUNCTION public.cancel_order_atomic(
    p_order_id UUID,
    p_operation_id TEXT,
    p_expected_row_version BIGINT,
    p_reason TEXT DEFAULT 'customer_requested'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_claims JSONB := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
    v_merchant_id UUID := NULLIF(v_claims->>'merchant_id', '')::UUID;
    v_user_id UUID := NULLIF(v_claims->>'sub', '')::UUID;
    v_order public.orders%ROWTYPE;
    v_new_version BIGINT;
    v_op_id TEXT := NULLIF(btrim(p_operation_id), '');
    v_previous_response JSONB;
    v_response JSONB;
    v_inserted INTEGER;
BEGIN
    IF v_merchant_id IS NULL OR p_order_id IS NULL OR v_op_id IS NULL
       OR p_expected_row_version IS NULL OR p_expected_row_version < 1 THEN
        RAISE EXCEPTION 'invalid_cancel_request' USING ERRCODE = '22023';
    END IF;
    PERFORM set_config('lock_timeout', '2000ms', true);

    -- Check idempotency
    INSERT INTO public.order_mutation_operations
        (merchant_id, operation_id, order_id, request)
    VALUES (
        v_merchant_id, v_op_id, p_order_id,
        jsonb_build_object('action', 'cancel', 'order_id', p_order_id, 'reason', p_reason, 'expected_version', p_expected_row_version)
    )
    ON CONFLICT (merchant_id, operation_id) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    IF v_inserted = 0 THEN
        SELECT response INTO v_previous_response
          FROM public.order_mutation_operations
         WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;
        IF v_previous_response IS NOT NULL THEN
            RETURN v_previous_response;
        END IF;
    END IF;

    SELECT * INTO v_order FROM public.orders
    WHERE id = p_order_id AND merchant_id = v_merchant_id
    FOR UPDATE NOWAIT;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'order_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF v_order.status = 'cancelled' THEN
        v_response := jsonb_build_object('order_id', p_order_id, 'status', 'cancelled', 'order_row_version', v_order.row_version);
        UPDATE public.order_mutation_operations SET response = v_response
        WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;
        RETURN v_response;
    END IF;

    IF v_order.status = 'completed' THEN
        RAISE EXCEPTION 'completed_order_cannot_be_cancelled_must_refund' USING ERRCODE = '22023';
    END IF;

    IF v_order.row_version <> p_expected_row_version THEN
        INSERT INTO public.sync_conflict_journal (
            merchant_id, branch_id, entity_type, entity_id,
            expected_version, server_version, resolution, details
        ) VALUES (
            v_merchant_id, v_order.branch_id, 'orders', p_order_id::text,
            p_expected_row_version, v_order.row_version, 'manual_required',
            jsonb_build_object('action', 'cancel', 'reason', p_reason)
        );

        RAISE EXCEPTION 'order_conflict id=% expected=% actual=%',
            p_order_id, p_expected_row_version, v_order.row_version
            USING ERRCODE = '40001';
    END IF;

    -- Cancel all active items
    UPDATE public.order_items
       SET status = 'cancelled'
     WHERE order_id = p_order_id AND merchant_id = v_merchant_id AND status <> 'cancelled';

    -- Update order to cancelled
    UPDATE public.orders
       SET status = 'cancelled',
           cancel_reason = p_reason,
           cancelled_at = now()
     WHERE id = p_order_id AND merchant_id = v_merchant_id
     RETURNING row_version INTO v_new_version;

    -- Release table if associated
    IF v_order.table_number IS NOT NULL AND upper(v_order.table_number) <> 'QUICK' THEN
        UPDATE public.restaurant_tables
           SET status = 'vacant'
         WHERE merchant_id = v_merchant_id AND table_number = v_order.table_number;
    END IF;

    v_response := jsonb_build_object(
        'order_id', p_order_id,
        'status', 'cancelled',
        'order_row_version', v_new_version,
        'reason', p_reason
    );

    UPDATE public.order_mutation_operations
       SET response = v_response
     WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;

    RETURN v_response;
END;
$$;

-- 4. Atomic Idempotent Order Refund
CREATE OR REPLACE FUNCTION public.refund_order_atomic(
    p_order_id UUID,
    p_operation_id TEXT,
    p_refund_amount NUMERIC,
    p_payment_id UUID DEFAULT NULL,
    p_reason TEXT DEFAULT 'customer_refund'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_claims JSONB := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
    v_merchant_id UUID := NULLIF(v_claims->>'merchant_id', '')::UUID;
    v_order public.orders%ROWTYPE;
    v_payment public.payments%ROWTYPE;
    v_op_id TEXT := NULLIF(btrim(p_operation_id), '');
    v_total_refunded NUMERIC := 0;
    v_new_version BIGINT;
    v_previous_response JSONB;
    v_response JSONB;
    v_inserted INTEGER;
    v_refund_id UUID := gen_random_uuid();
BEGIN
    IF v_merchant_id IS NULL OR p_order_id IS NULL OR v_op_id IS NULL
       OR p_refund_amount IS NULL OR p_refund_amount <= 0 THEN
        RAISE EXCEPTION 'invalid_refund_request' USING ERRCODE = '22023';
    END IF;
    PERFORM set_config('lock_timeout', '2000ms', true);

    -- Idempotency check
    INSERT INTO public.order_mutation_operations
        (merchant_id, operation_id, order_id, request)
    VALUES (
        v_merchant_id, v_op_id, p_order_id,
        jsonb_build_object('action', 'refund', 'order_id', p_order_id, 'amount', p_refund_amount, 'reason', p_reason)
    )
    ON CONFLICT (merchant_id, operation_id) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    IF v_inserted = 0 THEN
        SELECT response INTO v_previous_response
          FROM public.order_mutation_operations
         WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;
        IF v_previous_response IS NOT NULL THEN
            RETURN v_previous_response;
        END IF;
    END IF;

    SELECT * INTO v_order FROM public.orders
    WHERE id = p_order_id AND merchant_id = v_merchant_id
    FOR UPDATE NOWAIT;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'order_not_found' USING ERRCODE = 'P0002';
    END IF;

    -- Calculate already refunded amount
    SELECT COALESCE(SUM(amount), 0) INTO v_total_refunded
      FROM public.refund_transactions
     WHERE order_id = p_order_id AND merchant_id = v_merchant_id;

    IF (v_total_refunded + p_refund_amount) > (v_order.total + 0.05) THEN
        RAISE EXCEPTION 'refund_exceeds_order_total max=% requested=%',
            (v_order.total - v_total_refunded), p_refund_amount
            USING ERRCODE = '22023';
    END IF;

    -- Insert into refund_transactions
    INSERT INTO public.refund_transactions (
        id, merchant_id, branch_id, order_id, payment_id, amount, reason, created_at
    ) VALUES (
        v_refund_id, v_merchant_id, v_order.branch_id, p_order_id,
        p_payment_id, p_refund_amount, p_reason, now()
    );

    -- Advance order row_version
    UPDATE public.orders
       SET updated_at = now()
     WHERE id = p_order_id AND merchant_id = v_merchant_id
     RETURNING row_version INTO v_new_version;

    v_response := jsonb_build_object(
        'refund_id', v_refund_id,
        'order_id', p_order_id,
        'amount_refunded', p_refund_amount,
        'total_refunded', (v_total_refunded + p_refund_amount),
        'order_row_version', v_new_version,
        'status', 'refunded'
    );

    UPDATE public.order_mutation_operations
       SET response = v_response
     WHERE merchant_id = v_merchant_id AND operation_id = v_op_id;

    RETURN v_response;
END;
$$;

-- 5. Grants
REVOKE ALL ON FUNCTION public.transition_order_with_items(UUID, UUID, BIGINT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_order_atomic(UUID, TEXT, BIGINT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refund_order_atomic(UUID, TEXT, NUMERIC, UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.transition_order_with_items(UUID, UUID, BIGINT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_order_atomic(UUID, TEXT, BIGINT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.refund_order_atomic(UUID, TEXT, NUMERIC, UUID, TEXT) TO anon, authenticated, service_role;

COMMIT;
