BEGIN;

-- One vocabulary for every stock movement used by iOS and PostgreSQL.
ALTER TABLE public.inventory_transactions
    DROP CONSTRAINT IF EXISTS inventory_transactions_type_check;
ALTER TABLE public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_type_check CHECK (
        COALESCE(transaction_type, type) IN (
            'receive', 'waste', 'adjust', 'sell', 'void', 'opening',
            'return_to_supplier', 'refund_return', 'transfer_out', 'transfer_in'
        )
    );

ALTER TABLE public.inventory_transactions
    DROP CONSTRAINT IF EXISTS inventory_transactions_item_id_fkey;
ALTER TABLE public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_item_id_fkey
    FOREIGN KEY (item_id) REFERENCES public.inventory_items(id) ON DELETE RESTRICT;

-- Recipes use the same TEXT key as menu_items, and only one active ingredient
-- row is allowed for a menu item/inventory item pair.
DROP INDEX IF EXISTS public.idx_recipes_menu_item_text;
ALTER TABLE public.recipes ADD COLUMN IF NOT EXISTS quantity_unit TEXT;
ALTER TABLE public.recipes ALTER COLUMN menu_item_id TYPE TEXT USING menu_item_id::TEXT;
UPDATE public.recipes r
SET menu_item_id = NULL, is_deleted = TRUE, updated_at = now()
WHERE r.menu_item_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.menu_items m WHERE m.id = r.menu_item_id);
ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_menu_item_id_fkey;
ALTER TABLE public.recipes
    ADD CONSTRAINT recipes_menu_item_id_fkey
    FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id) ON DELETE CASCADE;
WITH ranked AS (
    SELECT id, row_number() OVER (
        PARTITION BY merchant_id, menu_item_id, inventory_item_id
        ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id
    ) AS rn
    FROM public.recipes
    WHERE COALESCE(is_deleted, FALSE) = FALSE
)
UPDATE public.recipes r
SET is_deleted = TRUE, updated_at = now()
FROM ranked x
WHERE r.id = x.id AND x.rn > 1;
CREATE UNIQUE INDEX IF NOT EXISTS recipes_one_active_ingredient
    ON public.recipes (merchant_id, menu_item_id, inventory_item_id)
    WHERE COALESCE(is_deleted, FALSE) = FALSE;

-- Immutable lot allocation is the evidence used by COGS, void, and refund.
CREATE TABLE IF NOT EXISTS public.inventory_lot_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    movement_id UUID NOT NULL REFERENCES public.inventory_transactions(id) ON DELETE RESTRICT,
    reference_id UUID,
    inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
    lot_id UUID NOT NULL REFERENCES public.inventory_lots(id) ON DELETE RESTRICT,
    quantity NUMERIC(12,4) NOT NULL CHECK (quantity > 0),
    cost_price NUMERIC(12,4) NOT NULL CHECK (cost_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (movement_id, lot_id)
);
CREATE INDEX IF NOT EXISTS inventory_lot_allocations_reference
    ON public.inventory_lot_allocations (merchant_id, reference_id, inventory_item_id);
ALTER TABLE public.inventory_lot_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS merchant_isolation_inventory_lot_allocations
    ON public.inventory_lot_allocations;
CREATE POLICY merchant_isolation_inventory_lot_allocations
    ON public.inventory_lot_allocations FOR ALL TO anon
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

-- inventory_lots previously had RLS enabled without a policy.
DROP POLICY IF EXISTS merchant_isolation_inventory_lots ON public.inventory_lots;
CREATE POLICY merchant_isolation_inventory_lots
    ON public.inventory_lots FOR ALL TO anon
    USING (merchant_id = public.get_active_merchant_id())
    WITH CHECK (merchant_id = public.get_active_merchant_id());

-- Preserve today's on-hand as an opening ledger entry before ledger enforcement.
INSERT INTO public.inventory_transactions (
    id, merchant_id, item_id, item_name, transaction_type, type, quantity,
    reference_id, notes, branch_id, cost_price, reason_code,
    is_synced, is_deleted, updated_at, created_at
)
SELECT gen_random_uuid(), i.merchant_id, i.id, i.name, 'opening', 'opening',
       i.current_quantity - COALESCE(x.ledger_quantity, 0), i.id,
       'Automatic opening balance created during ledger migration',
       i.branch_id, i.cost_price, 'ledger_migration', TRUE, FALSE, now(), now()
FROM public.inventory_items i
LEFT JOIN (
    SELECT merchant_id, item_id, SUM(quantity) AS ledger_quantity
    FROM public.inventory_transactions
    WHERE COALESCE(is_deleted, FALSE) = FALSE AND item_id IS NOT NULL
    GROUP BY merchant_id, item_id
) x ON x.merchant_id = i.merchant_id AND x.item_id = i.id
WHERE COALESCE(i.is_deleted, FALSE) = FALSE
  AND abs(i.current_quantity - COALESCE(x.ledger_quantity, 0)) > 0.0001
ON CONFLICT ON CONSTRAINT inventory_transactions_reference_unique DO NOTHING;

-- All inserts, including legacy clients, are normalized and locked here.
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
    SELECT * INTO v_item FROM public.inventory_items
    WHERE id = NEW.item_id AND merchant_id = NEW.merchant_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Inventory item not found for merchant'; END IF;

    NEW.transaction_type := v_type;
    NEW.type := v_type;
    NEW.quantity := CASE
        WHEN v_type IN ('receive','void','opening','refund_return','transfer_in') THEN abs(NEW.quantity)
        WHEN v_type IN ('sell','waste','return_to_supplier','transfer_out') THEN -abs(NEW.quantity)
        ELSE NEW.quantity
    END;
    IF v_item.current_quantity + NEW.quantity < -0.0001 THEN
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

CREATE OR REPLACE FUNCTION public.inventory_movement_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_remaining NUMERIC := abs(NEW.quantity);
    v_take NUMERIC;
    v_lot RECORD;
    v_original RECORD;
BEGIN
    UPDATE public.inventory_items
    SET current_quantity = current_quantity + NEW.quantity,
        updated_at = now(), is_synced = TRUE
    WHERE id = NEW.item_id AND merchant_id = NEW.merchant_id;

    IF NEW.transaction_type IN ('sell','waste','return_to_supplier','transfer_out') THEN
        FOR v_lot IN
            SELECT * FROM public.inventory_lots
            WHERE merchant_id = NEW.merchant_id
              AND inventory_item_id = NEW.item_id
              AND COALESCE(is_deleted, FALSE) = FALSE
              AND remaining_quantity > 0
            ORDER BY expiry_date ASC NULLS LAST, received_date ASC, id
            FOR UPDATE
        LOOP
            EXIT WHEN v_remaining <= 0;
            v_take := least(v_remaining, v_lot.remaining_quantity);
            UPDATE public.inventory_lots
            SET remaining_quantity = remaining_quantity - v_take,
                updated_at = now(), is_synced = TRUE
            WHERE id = v_lot.id;
            INSERT INTO public.inventory_lot_allocations (
                merchant_id, movement_id, reference_id, inventory_item_id,
                lot_id, quantity, cost_price
            ) VALUES (
                NEW.merchant_id, NEW.id, NEW.reference_id, NEW.item_id,
                v_lot.id, v_take, v_lot.lot_cost_price
            ) ON CONFLICT (movement_id, lot_id) DO NOTHING;
            v_remaining := v_remaining - v_take;
        END LOOP;
    ELSIF NEW.transaction_type IN ('void','refund_return') AND NEW.reference_id IS NOT NULL THEN
        FOR v_original IN
            SELECT a.lot_id, a.quantity
            FROM public.inventory_transactions t
            JOIN public.inventory_lot_allocations a ON a.movement_id = t.id
            WHERE t.merchant_id = NEW.merchant_id
              AND t.item_id = NEW.item_id
              AND t.reference_id = NEW.reference_id
              AND t.transaction_type = 'sell'
        LOOP
            UPDATE public.inventory_lots
            SET remaining_quantity = least(initial_quantity, remaining_quantity + v_original.quantity),
                updated_at = now(), is_synced = TRUE
            WHERE id = v_original.lot_id;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS inventory_movement_before_insert ON public.inventory_transactions;
CREATE TRIGGER inventory_movement_before_insert
BEFORE INSERT ON public.inventory_transactions
FOR EACH ROW EXECUTE FUNCTION public.inventory_movement_before_insert();
DROP TRIGGER IF EXISTS inventory_movement_after_insert ON public.inventory_transactions;
CREATE TRIGGER inventory_movement_after_insert
AFTER INSERT ON public.inventory_transactions
FOR EACH ROW EXECUTE FUNCTION public.inventory_movement_after_insert();

-- Idempotent movement API. The trigger above is the only place that mutates on-hand.
CREATE OR REPLACE FUNCTION public.apply_inventory_movement(
    p_movement_id UUID,
    p_merchant_id UUID,
    p_item_id UUID,
    p_type TEXT,
    p_quantity NUMERIC,
    p_reference_id UUID,
    p_branch_id UUID,
    p_cost_price NUMERIC,
    p_notes TEXT,
    p_reason_code TEXT,
    p_created_at TIMESTAMPTZ,
    p_audit_signature TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
    IF public.get_active_merchant_id() IS NOT NULL
       AND public.get_active_merchant_id() <> p_merchant_id THEN
        RAISE EXCEPTION 'Merchant scope mismatch';
    END IF;
    SELECT id INTO v_id FROM public.inventory_transactions
    WHERE id = p_movement_id
       OR (p_reference_id IS NOT NULL
           AND merchant_id = p_merchant_id AND item_id = p_item_id
           AND transaction_type = p_type AND reference_id = p_reference_id)
    LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    INSERT INTO public.inventory_transactions (
        id, merchant_id, item_id, item_name, transaction_type, type, quantity,
        reference_id, branch_id, cost_price, notes, reason_code, audit_signature,
        is_synced, is_deleted, created_at, updated_at
    ) VALUES (
        p_movement_id, p_merchant_id, p_item_id, '', p_type, p_type, p_quantity,
        p_reference_id, p_branch_id, p_cost_price, p_notes, p_reason_code,
        p_audit_signature, TRUE, FALSE, COALESCE(p_created_at, now()), now()
    ) RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- Both sides are one PostgreSQL transaction and rows are locked in stable order.
CREATE OR REPLACE FUNCTION public.transfer_inventory_atomic(
    p_transfer_id UUID,
    p_merchant_id UUID,
    p_source_item_id UUID,
    p_target_item_id UUID,
    p_quantity NUMERIC,
    p_notes TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_source public.inventory_items%ROWTYPE;
    v_target public.inventory_items%ROWTYPE;
BEGIN
    IF public.get_active_merchant_id() IS NOT NULL
       AND public.get_active_merchant_id() <> p_merchant_id THEN
        RAISE EXCEPTION 'Merchant scope mismatch';
    END IF;
    IF p_quantity <= 0 OR p_source_item_id = p_target_item_id THEN
        RAISE EXCEPTION 'Invalid transfer';
    END IF;
    IF (
        SELECT count(*) = 2
        FROM public.inventory_transactions
        WHERE merchant_id = p_merchant_id AND reference_id = p_transfer_id
          AND (
              (item_id = p_source_item_id AND transaction_type = 'transfer_out') OR
              (item_id = p_target_item_id AND transaction_type = 'transfer_in')
          )
    ) THEN
        RETURN p_transfer_id;
    END IF;
    PERFORM id FROM public.inventory_items
    WHERE id IN (p_source_item_id, p_target_item_id) AND merchant_id = p_merchant_id
    ORDER BY id FOR UPDATE;
    SELECT * INTO v_source FROM public.inventory_items WHERE id = p_source_item_id;
    SELECT * INTO v_target FROM public.inventory_items WHERE id = p_target_item_id;
    IF v_source.id IS NULL OR v_target.id IS NULL THEN RAISE EXCEPTION 'Transfer item not found'; END IF;
    IF v_source.current_quantity < p_quantity THEN RAISE EXCEPTION 'Insufficient source stock'; END IF;

    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), p_merchant_id, p_source_item_id, 'transfer_out',
        p_quantity, p_transfer_id, v_source.branch_id, v_source.cost_price,
        p_notes, 'transfer', now(), NULL
    );
    PERFORM public.apply_inventory_movement(
        gen_random_uuid(), p_merchant_id, p_target_item_id, 'transfer_in',
        p_quantity, p_transfer_id, v_target.branch_id, v_source.cost_price,
        p_notes, 'transfer', now(), NULL
    );
    RETURN p_transfer_id;
END;
$$;

-- Server-side order paths use the same conversion/yield rule as iOS.
CREATE OR REPLACE FUNCTION public.inventory_required_quantity(
    p_quantity NUMERIC,
    p_from_unit TEXT,
    p_to_unit TEXT,
    p_yield_percentage NUMERIC,
    p_sale_quantity NUMERIC
) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE
AS $$
WITH units AS (
    SELECT lower(COALESCE(p_from_unit, p_to_unit, '')) AS f,
           lower(COALESCE(p_to_unit, p_from_unit, '')) AS t
), factors AS (
    SELECT
        CASE f WHEN 'kg' THEN 1000 WHEN 'g' THEN 1 WHEN 'mg' THEN .001
               WHEN 'liter' THEN 1000 WHEN 'ml' THEN 1 ELSE 1 END AS ff,
        CASE t WHEN 'kg' THEN 1000 WHEN 'g' THEN 1 WHEN 'mg' THEN .001
               WHEN 'liter' THEN 1000 WHEN 'ml' THEN 1 ELSE 1 END AS tf,
        CASE WHEN f IN ('kg','g','mg') THEN 'mass'
             WHEN f IN ('liter','ml') THEN 'volume' ELSE 'count' END AS fg,
        CASE WHEN t IN ('kg','g','mg') THEN 'mass'
             WHEN t IN ('liter','ml') THEN 'volume' ELSE 'count' END AS tg
    FROM units
)
SELECT greatest(p_quantity, 0)
       * CASE WHEN fg = tg THEN ff / tf ELSE 1 END
       * greatest(p_sale_quantity, 0)
       / (least(greatest(COALESCE(p_yield_percentage, 100), .01), 100) / 100)
FROM factors;
$$;

CREATE OR REPLACE FUNCTION public.deduct_stock_on_order_item_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_branch_id UUID;
    v_required NUMERIC;
BEGIN
    IF NOT (
        NEW.status IN ('cooking','served')
        AND (TG_OP = 'INSERT' OR OLD.status IS NULL OR OLD.status = 'pending')
    ) THEN RETURN NEW; END IF;
    v_branch_id := NEW.branch_id;
    IF v_branch_id IS NULL THEN
        SELECT branch_id INTO v_branch_id FROM public.orders WHERE id = NEW.order_id;
    END IF;

    FOR r IN
        SELECT x.inventory_item_id, x.quantity_required, x.quantity_unit,
               x.yield_percentage, i.unit, i.cost_price
        FROM public.recipes x
        JOIN public.inventory_items i ON i.id = x.inventory_item_id
        WHERE x.menu_item_id = NEW.item_id
          AND x.merchant_id = NEW.merchant_id
          AND COALESCE(x.is_deleted,FALSE) = FALSE
          AND COALESCE(i.is_deleted,FALSE) = FALSE
          AND (v_branch_id IS NULL OR i.branch_id = v_branch_id)
    LOOP
        v_required := public.inventory_required_quantity(
            r.quantity_required, r.quantity_unit, r.unit,
            r.yield_percentage, NEW.quantity
        );
        PERFORM public.apply_inventory_movement(
            gen_random_uuid(), NEW.merchant_id, r.inventory_item_id, 'sell',
            v_required, NEW.id, v_branch_id, r.cost_price,
            'Order item ' || NEW.id, 'sale', now(), NULL
        );
    END LOOP;

    FOR r IN
        SELECT m.inventory_item_id, m.quantity_required, m.name, oim.id AS reference_id,
               i.cost_price
        FROM public.order_item_modifiers oim
        JOIN public.modifiers m ON m.id = oim.modifier_id
        JOIN public.inventory_items i ON i.id = m.inventory_item_id
        WHERE oim.order_item_id = NEW.id
          AND COALESCE(oim.is_deleted,FALSE) = FALSE
          AND COALESCE(m.is_deleted,FALSE) = FALSE
          AND (v_branch_id IS NULL OR i.branch_id = v_branch_id)
    LOOP
        PERFORM public.apply_inventory_movement(
            gen_random_uuid(), NEW.merchant_id, r.inventory_item_id, 'sell',
            greatest(COALESCE(r.quantity_required,0),0) * NEW.quantity,
            r.reference_id, v_branch_id, r.cost_price,
            'Order modifier ' || r.name, 'sale', now(), NULL
        );
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.revert_stock_on_void_or_cancel_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r RECORD;
BEGIN
    IF NOT (NEW.status = 'cancelled' AND OLD.status IN ('cooking','ready','served','alert')) THEN
        RETURN NEW;
    END IF;
    FOR r IN
        SELECT t.*
        FROM public.inventory_transactions t
        WHERE t.merchant_id = NEW.merchant_id
          AND t.transaction_type = 'sell'
          AND (
              t.reference_id = NEW.id OR
              t.reference_id IN (
                  SELECT id FROM public.order_item_modifiers
                  WHERE order_item_id = NEW.id
              )
          )
          AND COALESCE(t.is_deleted,FALSE) = FALSE
    LOOP
        PERFORM public.apply_inventory_movement(
            gen_random_uuid(), r.merchant_id, r.item_id, 'void',
            abs(r.quantity), r.reference_id, r.branch_id, r.cost_price,
            'Void original movement ' || r.id, 'void', now(), NULL
        );
    END LOOP;
    RETURN NEW;
END;
$$;

-- Reconciliation is measurable and repairable; a zero-row result means balanced.
CREATE OR REPLACE VIEW public.inventory_reconciliation AS
SELECT i.merchant_id, i.branch_id, i.id AS inventory_item_id, i.name,
       i.current_quantity AS on_hand,
       COALESCE(sum(t.quantity) FILTER (WHERE COALESCE(t.is_deleted,FALSE)=FALSE), 0) AS ledger_quantity,
       i.current_quantity
         - COALESCE(sum(t.quantity) FILTER (WHERE COALESCE(t.is_deleted,FALSE)=FALSE), 0) AS variance
FROM public.inventory_items i
LEFT JOIN public.inventory_transactions t
  ON t.merchant_id = i.merchant_id AND t.item_id = i.id
GROUP BY i.merchant_id, i.branch_id, i.id, i.name, i.current_quantity;

GRANT EXECUTE ON FUNCTION public.apply_inventory_movement(
    UUID,UUID,UUID,TEXT,NUMERIC,UUID,UUID,NUMERIC,TEXT,TEXT,TIMESTAMPTZ,TEXT
) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.transfer_inventory_atomic(
    UUID,UUID,UUID,UUID,NUMERIC,TEXT
) TO anon, authenticated, service_role;
GRANT SELECT ON public.inventory_reconciliation TO anon, authenticated, service_role;

COMMIT;
