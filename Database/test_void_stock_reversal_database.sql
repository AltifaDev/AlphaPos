-- =========================================================================
-- AlphaPos Database Integration Test: Void/Cancel Stock Reversal with Yield
-- Run in PostgreSQL / Supabase SQL Editor.
-- Enclosed in a Transaction (BEGIN / ROLLBACK) to guarantee no pollution of DB.
-- =========================================================================

BEGIN;

-- 1. Setup Mock Seed Data for Testing
DO $$
DECLARE
    v_merchant_id UUID := '00000000-0000-0000-0000-000000000001';
    v_branch_id UUID := '00000000-0000-0000-0000-000000000002';

    v_raw_beef_id UUID := '11111111-1111-1111-1111-111111111111';
    v_raw_onion_id UUID := '22222222-2222-2222-2222-222222222222';

    v_menu_burger_id UUID := '33333333-3333-3333-3333-333333333333';

    v_order_id UUID := '44444444-4444-4444-4444-444444444444';
    v_order_item_id UUID := '55555555-5555-5555-5555-555555555555';
    v_order_item_id_2 UUID := '66666666-6666-6666-6666-666666666666';

    v_beef_qty DECIMAL;
    v_onion_qty DECIMAL;
    v_txn_count INTEGER;
    v_void_txn_count INTEGER;
BEGIN
    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE '🧪 Starting Database Integration Test: Void/Cancel Stock Reversal with Yield';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

    -- A. Seed Merchant
    INSERT INTO public.merchants (id, name, email)
    VALUES (v_merchant_id, 'Integration Test Shop', 'test@alphapos.com');

    -- B. Seed Branches
    BEGIN
        INSERT INTO public.branches (id, merchant_id, name)
        VALUES (v_branch_id, v_merchant_id, 'Test Branch');
    EXCEPTION WHEN OTHERS THEN
        v_branch_id := NULL; -- fallback to null if branches doesn't exist
    END;

    -- C. Seed Raw Materials (Inventory Items with 100 starting quantity)
    INSERT INTO public.inventory_items (id, merchant_id, branch_id, name, current_quantity, sku, category)
    VALUES
        (v_raw_beef_id, v_merchant_id, v_branch_id, 'Beef Meat (Raw)', 100.00, 'SKU-BEEF', 'Meat'),
        (v_raw_onion_id, v_merchant_id, v_branch_id, 'Onion (Raw)', 100.00, 'SKU-ONION', 'Vegetables');

    -- D. Seed Menu Item (Burger)
    INSERT INTO public.menu_items (id, merchant_id, name, price, category)
    VALUES (v_menu_burger_id::text, v_merchant_id, 'Super Beef Burger', 180.00, 'Burgers');

    -- E. Seed Recipe (Burger requires 1.5 units Beef with 75% Yield (waste 25%), 0.5 units Onion with 100% Yield)
    -- Beef calculation: 1.5 * (100 / 75) = 2.0 actual units deducted per burger.
    INSERT INTO public.recipes (id, merchant_id, menu_item_id, inventory_item_id, quantity_required, yield_percentage)
    VALUES
        (uuid_generate_v4(), v_merchant_id, v_menu_burger_id, v_raw_beef_id, 1.50, 75.00), -- 75% Yield
        (uuid_generate_v4(), v_merchant_id, v_menu_burger_id, v_raw_onion_id, 0.50, 100.00); -- 100% Yield

    -- F. Seed Order
    INSERT INTO public.orders (id, merchant_id, order_number, table_number, total, status)
    VALUES (v_order_id, v_merchant_id, 'TEST-ORD-01', 'T-05', 360.00, 'preparing');

    RAISE NOTICE '✅ Seed data completed successfully.';

    -- ────────────────────────────────────────────────────────
    -- TEST CASE 1: ORDER INSERT (Deduction with Yield)
    -- ────────────────────────────────────────────────────────
    RAISE NOTICE '🔄 Running Test Case 1: Order Item inserted (Deduction with Yield)...';

    -- Ordered Quantity: 2 burgers.
    -- Expected Beef deducted: 1.5 * (100/75) * 2 = 4.0 units. Remaining: 100.0 - 4.0 = 96.0
    -- Expected Onion deducted: 0.5 * (100/100) * 2 = 1.0 units. Remaining: 100.0 - 1.0 = 99.0
    INSERT INTO public.order_items (id, merchant_id, order_id, item_name, quantity, price, status, item_id, branch_id)
    VALUES (v_order_item_id, v_merchant_id, v_order_id, 'Super Beef Burger', 2, 180.00, 'cooking', v_menu_burger_id::text, v_branch_id);

    SELECT current_quantity INTO v_beef_qty FROM public.inventory_items WHERE id = v_raw_beef_id;
    SELECT current_quantity INTO v_onion_qty FROM public.inventory_items WHERE id = v_raw_onion_id;

    RAISE NOTICE '  Beef Qty remaining: % (Expected: 96.00)', v_beef_qty;
    RAISE NOTICE '  Onion Qty remaining: % (Expected: 99.00)', v_onion_qty;

    IF v_beef_qty = 96.00 AND v_onion_qty = 99.00 THEN
        RAISE NOTICE '  => Test Case 1 (Yield Deduction): PASS ✅';
    ELSE
        RAISE EXCEPTION '  => Test Case 1 (Yield Deduction): FAIL ❌ (Incorrect stock deduction)';
    END IF;

    -- ────────────────────────────────────────────────────────
    -- TEST CASE 2: VOID/CANCEL ORDER (Reversal with Yield)
    -- ────────────────────────────────────────────────────────
    RAISE NOTICE '🔄 Running Test Case 2: Order Item updated to cancelled (Reversal with Yield)...';

    UPDATE public.order_items
    SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP
    WHERE id = v_order_item_id;

    -- Verify stocks (Expected: restored to 100.00 each)
    SELECT current_quantity INTO v_beef_qty FROM public.inventory_items WHERE id = v_raw_beef_id;
    SELECT current_quantity INTO v_onion_qty FROM public.inventory_items WHERE id = v_raw_onion_id;

    RAISE NOTICE '  Beef Qty remaining: % (Expected: 100.00)', v_beef_qty;
    RAISE NOTICE '  Onion Qty remaining: % (Expected: 100.00)', v_onion_qty;

    IF v_beef_qty = 100.00 AND v_onion_qty = 100.00 THEN
        RAISE NOTICE '  => Test Case 2 (Yield Reversal): PASS ✅';
    ELSE
        RAISE EXCEPTION '  => Test Case 2 (Yield Reversal): FAIL ❌ (Stock not restored correctly)';
    END IF;

    -- Verify transactions
    SELECT COUNT(*) INTO v_void_txn_count
    FROM public.inventory_transactions
    WHERE reference_id = v_order_item_id AND transaction_type = 'void';

    RAISE NOTICE '  Void Reversal Transactions written: % (Expected: 2)', v_void_txn_count;
    IF v_void_txn_count = 2 THEN
        RAISE NOTICE '  => Void Reversal Transaction Audit Log: PASS ✅';
    ELSE
        RAISE EXCEPTION '  => Void Reversal Transaction Audit Log: FAIL ❌';
    END IF;

    RAISE NOTICE '══════════════════════════════════════════════════════════════';
    RAISE NOTICE '🎉 ALL DATABASE YIELD & VOID INTEGRATION TESTS PASSED SUCCESSFULLY!';
    RAISE NOTICE '══════════════════════════════════════════════════════════════';

END;
$$;

-- Rollback the transaction to keep production database clean
ROLLBACK;
