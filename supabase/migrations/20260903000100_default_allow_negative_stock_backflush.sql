-- Migration: Default Allow Negative Stock for Backflush Inventory Model
-- Enables unrestricted front-of-house sales by allowing raw ingredient stocks to be deducted into negative balances.
-- Staff can manually 86/sold-out items when physically unavailable.

-- 1. Alter the default value for out_of_stock_policy to 'allow_negative'
ALTER TABLE public.inventory_items
    ALTER COLUMN out_of_stock_policy SET DEFAULT 'allow_negative';

-- 2. Update existing items from 'block' to 'allow_negative' so stores can sell without disruption
UPDATE public.inventory_items
SET out_of_stock_policy = 'allow_negative'
WHERE out_of_stock_policy = 'block';

-- 3. Ensure constraint allows 'allow_negative' and 'block'
ALTER TABLE public.inventory_items
    DROP CONSTRAINT IF EXISTS inventory_items_out_of_stock_policy_check,
    ADD CONSTRAINT inventory_items_out_of_stock_policy_check
        CHECK (out_of_stock_policy IN ('block', 'allow_negative'));

-- 4. Re-verify the inventory movement trigger to ensure 'sell' transactions continue
-- to pass atomically when out_of_stock_policy = 'allow_negative'
CREATE OR REPLACE FUNCTION public.inventory_movement_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item public.inventory_items%ROWTYPE;
    v_type TEXT := COALESCE(NEW.transaction_type, NEW.type);
BEGIN
    IF v_type NOT IN (
        'receive', 'waste', 'adjust', 'sell', 'void', 'opening',
        'return_to_supplier', 'refund_return', 'transfer_out', 'transfer_in'
    ) THEN
        RAISE EXCEPTION 'Unsupported inventory movement type: %', v_type;
    END IF;

    SELECT * INTO v_item
    FROM public.inventory_items
    WHERE id = NEW.item_id AND merchant_id = NEW.merchant_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory item not found for merchant';
    END IF;

    NEW.transaction_type := v_type;
    NEW.type := v_type;
    NEW.quantity := CASE
        WHEN v_type IN ('receive','void','opening','refund_return','transfer_in') THEN abs(NEW.quantity)
        WHEN v_type IN ('sell','waste','return_to_supplier','transfer_out') THEN -abs(NEW.quantity)
        ELSE NEW.quantity
    END;

    -- Only reject if item is explicitly 'block' and has insufficient stock.
    -- Default 'allow_negative' permits POS sales to continue seamlessly.
    IF v_item.current_quantity + NEW.quantity < -0.0001
       AND NOT (v_type = 'sell' AND v_item.out_of_stock_policy = 'allow_negative') THEN
        RAISE EXCEPTION 'Insufficient stock: item %, available %, requested %',
            NEW.item_id, v_item.current_quantity, abs(NEW.quantity);
    END IF;

    NEW.item_name := COALESCE(NULLIF(NEW.item_name, ''), v_item.name);
    NEW.cost_price := COALESCE(NEW.cost_price, v_item.cost_price);
    NEW.branch_id := COALESCE(NEW.branch_id, v_item.branch_id);
    NEW.updated_at := COALESCE(NEW.updated_at, now());
    NEW.created_at := COALESCE(NEW.created_at, now());
    RETURN NEW;
END;
$$;

-- 5. Add index for fast querying of negative stock items (for reconciliation & variance dashboards)
CREATE INDEX IF NOT EXISTS idx_inventory_items_negative_stock
    ON public.inventory_items (merchant_id, branch_id, current_quantity)
    WHERE COALESCE(is_deleted, FALSE) = FALSE AND current_quantity < 0;

COMMENT ON COLUMN public.inventory_items.out_of_stock_policy IS
    'allow_negative (default) permits POS backflush selling; block rejects movements below zero.';
