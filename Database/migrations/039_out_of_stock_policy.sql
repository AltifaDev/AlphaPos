-- Out-of-stock sale policy and negative inventory support.
-- Existing items remain strict by default. Only explicitly configured items may go negative.

ALTER TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS out_of_stock_policy TEXT NOT NULL DEFAULT 'block';

UPDATE public.inventory_items
SET out_of_stock_policy = 'block'
WHERE out_of_stock_policy IS NULL
   OR out_of_stock_policy NOT IN ('block', 'allow_negative');

ALTER TABLE public.inventory_items
    DROP CONSTRAINT IF EXISTS inventory_items_out_of_stock_policy_check,
    ADD CONSTRAINT inventory_items_out_of_stock_policy_check
        CHECK (out_of_stock_policy IN ('block', 'allow_negative'));

CREATE INDEX IF NOT EXISTS idx_inventory_items_negative_stock
    ON public.inventory_items (merchant_id, branch_id, current_quantity)
    WHERE COALESCE(is_deleted, FALSE) = FALSE AND current_quantity < 0;

-- Replaces the ledger guard so the database remains the atomic source of truth:
-- strict items reject overselling while allow_negative items accept it.
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

COMMENT ON COLUMN public.inventory_items.out_of_stock_policy IS
    'block rejects movements below zero; allow_negative permits POS overselling/backorders.';
