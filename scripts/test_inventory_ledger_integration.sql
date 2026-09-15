\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_merchant UUID;
    v_branch UUID;
    v_target_branch UUID;
    v_source UUID := gen_random_uuid();
    v_target UUID := gen_random_uuid();
    v_manual UUID := gen_random_uuid();
    v_lot UUID := gen_random_uuid();
    v_sale UUID := gen_random_uuid();
    v_sale_ref UUID := gen_random_uuid();
    v_refund_sale_ref UUID := gen_random_uuid();
    v_transfer UUID := gen_random_uuid();
    v_before NUMERIC;
    v_source_qty NUMERIC;
    v_target_qty NUMERIC;
    v_variance NUMERIC;
    v_required NUMERIC;
    v_lot_remaining NUMERIC;
    v_count INTEGER;
BEGIN
    SELECT id INTO v_merchant FROM public.merchants ORDER BY created_at LIMIT 1;
    IF v_merchant IS NULL THEN RAISE EXCEPTION 'Test needs one merchant'; END IF;
    -- Inventory RPCs enforce the same tenant context used by PostgREST.
    PERFORM set_config('request.jwt.claims', json_build_object(
        'app_metadata', json_build_object('merchant_id', v_merchant::text)
    )::text, true);
    SELECT id INTO v_branch FROM public.branches
    WHERE merchant_id = v_merchant ORDER BY created_at LIMIT 1;
    SELECT id INTO v_target_branch FROM public.branches
    WHERE merchant_id = v_merchant AND id <> v_branch ORDER BY created_at LIMIT 1;
    IF v_target_branch IS NULL THEN
        v_target_branch := gen_random_uuid();
        INSERT INTO public.branches (id, merchant_id, name, branch_code)
        VALUES (v_target_branch, v_merchant, 'Inventory E2E Target',
                'E2E-' || substr(v_target_branch::text, 1, 8));
    END IF;

    INSERT INTO public.inventory_items (
        id, merchant_id, branch_id, name, sku, unit, current_quantity,
        reorder_level, cost_price, is_synced, is_deleted
    ) VALUES
        (v_source, v_merchant, v_branch, 'IT Source', 'IT-' || v_source, 'piece', 0, 0, 7.5, TRUE, FALSE);
    -- Insert separately: the operational row-version trigger is row-oriented
    -- and legacy staging snapshots can exhibit pathological multi-row behavior.
    INSERT INTO public.inventory_items (
        id, merchant_id, branch_id, name, sku, unit, current_quantity,
        reorder_level, cost_price, is_synced, is_deleted
    ) VALUES
        (v_target, v_merchant, v_target_branch, 'IT Target', 'IT-' || v_target, 'piece', 0, 0, 7.5, TRUE, FALSE);

    INSERT INTO public.inventory_items (
        id, merchant_id, branch_id, name, sku, unit, current_quantity,
        reorder_level, cost_price, is_synced, is_deleted
    ) VALUES
        (v_manual, v_merchant, v_branch, 'IT Manual', 'IT-' || v_manual, 'piece', 0, 0, 2, TRUE, FALSE);

    -- Nil-reference manual events are distinct ledger rows. Business metadata
    -- is part of the same privileged RPC; no client PATCH is required.
    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), v_merchant, v_manual, 'receive', 3, NULL,
        v_branch, 2, 'manual receive one', 'receive', now(), NULL,
        current_date, NULL
    );
    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), v_merchant, v_manual, 'receive', 4, NULL,
        v_branch, 2, 'manual receive two', 'receive', now(), NULL,
        current_date, NULL
    );
    SELECT count(*) INTO v_count FROM public.inventory_transactions
    WHERE merchant_id = v_merchant AND item_id = v_manual
      AND transaction_type = 'receive' AND reference_id IS NULL
      AND business_date = current_date;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Nil-reference manual movements collapsed or lost metadata: %', v_count;
    END IF;
    SELECT current_quantity INTO v_source_qty FROM public.inventory_items WHERE id = v_manual;
    IF v_source_qty <> 7 THEN
        RAISE EXCEPTION 'Manual receive contract expected 7, got %', v_source_qty;
    END IF;
    RAISE NOTICE 'ledger-e2e: distinct manual receives + atomic metadata protected';

    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), v_merchant, v_source, 'opening', 100, v_source,
        v_branch, 7.5, 'integration opening', 'test', now(), NULL
    );
    INSERT INTO public.inventory_lots (
        id, merchant_id, branch_id, inventory_item_id, lot_number,
        initial_quantity, remaining_quantity, lot_cost_price, is_synced
    ) VALUES (v_lot, v_merchant, v_branch, v_source, 'IT-LOT', 100, 100, 7.5, TRUE);
    RAISE NOTICE 'ledger-e2e: seeded';

    SELECT public.inventory_required_quantity(0.5, 'kg', 'g', 80, 2)
    INTO v_required;
    IF v_required <> 1250 THEN
        RAISE EXCEPTION 'Shared unit/yield calculator returned %, expected 1250', v_required;
    END IF;

    -- Client A went offline, then Client B and retry submit the same business event.
    PERFORM public.apply_inventory_movement(
        v_sale, v_merchant, v_source, 'sell', 20, v_sale_ref,
        v_branch, 7.5, 'client A offline sale', 'sale', now(), NULL
    );
    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), v_merchant, v_source, 'sell', 20, v_sale_ref,
        v_branch, 7.5, 'client B duplicate retry', 'sale', now(), NULL
    );
    SELECT count(*) INTO v_count FROM public.inventory_transactions
    WHERE merchant_id = v_merchant AND item_id = v_source
      AND transaction_type = 'sell' AND reference_id = v_sale_ref;
    IF v_count <> 1 THEN RAISE EXCEPTION 'Duplicate sale was not idempotent'; END IF;
    RAISE NOTICE 'ledger-e2e: duplicate sale protected';

    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), v_merchant, v_source, 'void', 20, v_sale_ref,
        v_branch, 7.5, 'void original sale', 'void', now(), NULL
    );

    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), v_merchant, v_source, 'sell', 10, v_refund_sale_ref,
        v_branch, 7.5, 'sale to refund', 'sale', now(), NULL
    );
    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), v_merchant, v_source, 'refund_return', 10, v_refund_sale_ref,
        v_branch, 7.5, 'refund original sale', 'refund', now(), NULL
    );
    SELECT remaining_quantity INTO v_lot_remaining
    FROM public.inventory_lots WHERE id = v_lot;
    IF v_lot_remaining <> 100 THEN
        RAISE EXCEPTION 'Void/refund did not restore original lot allocation: %', v_lot_remaining;
    END IF;
    RAISE NOTICE 'ledger-e2e: void/refund restored lot';

    PERFORM public.transfer_inventory_atomic(
        v_transfer, v_merchant, v_source, v_target, 30, 'two-client transfer'
    );
    RAISE NOTICE 'ledger-e2e: transfer complete';
    -- Retry must not create either side twice.
    PERFORM public.transfer_inventory_atomic(
        v_transfer, v_merchant, v_source, v_target, 30, 'duplicate transfer retry'
    );

    SELECT current_quantity INTO v_source_qty FROM public.inventory_items WHERE id = v_source;
    SELECT current_quantity INTO v_target_qty FROM public.inventory_items WHERE id = v_target;
    IF v_source_qty <> 70 OR v_target_qty <> 30 THEN
        RAISE EXCEPTION 'Unexpected on-hand after lifecycle: source %, target %',
            v_source_qty, v_target_qty;
    END IF;

    SELECT count(*) INTO v_count FROM public.inventory_transactions
    WHERE merchant_id = v_merchant AND reference_id = v_transfer
      AND transaction_type IN ('transfer_out','transfer_in');
    IF v_count <> 2 THEN RAISE EXCEPTION 'Transfer retry was not idempotent'; END IF;

    SELECT max(abs(variance)) INTO v_variance
    FROM public.inventory_reconciliation
    WHERE inventory_item_id IN (v_source, v_target);
    IF COALESCE(v_variance, 0) > .0001 THEN
        RAISE EXCEPTION 'Ledger reconciliation variance: %', v_variance;
    END IF;
    RAISE NOTICE 'ledger-e2e: reconciliation complete';

    SELECT current_quantity INTO v_before FROM public.inventory_items WHERE id = v_source;
    BEGIN
        PERFORM public.transfer_inventory_atomic(
            gen_random_uuid(), v_merchant, v_source, v_target, 1000, 'must fail'
        );
        RAISE EXCEPTION 'Over-transfer did not fail';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'Over-transfer did not fail' THEN RAISE; END IF;
    END;
    SELECT current_quantity INTO v_source_qty FROM public.inventory_items WHERE id = v_source;
    IF v_source_qty <> v_before THEN RAISE EXCEPTION 'Failed transfer was not atomic'; END IF;

    RAISE NOTICE 'PASS inventory ledger integration: offline/retry/duplicate/void/refund/transfer';
END;
$$;

ROLLBACK;
