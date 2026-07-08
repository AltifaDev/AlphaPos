-- PostgreSQL Triggers for AlphaPos
-- =========================================================================
-- TRIGGER 1: Auto-Deduct Inventory on Cooking / Serving of Order Items
-- =========================================================================

CREATE OR REPLACE FUNCTION public.deduct_stock_on_order_item_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    r_recipe RECORD;
    r_modifier RECORD;
    v_branch_id UUID;
    v_transaction_exists BOOLEAN;
BEGIN
    IF NOT (
        NEW.status IN ('cooking', 'served')
        AND (TG_OP = 'INSERT' OR OLD.status IS NULL OR OLD.status = 'pending')
    ) THEN
        RETURN NEW;
    END IF;

    v_branch_id := NEW.branch_id;
    IF v_branch_id IS NULL THEN
        SELECT o.branch_id
        INTO v_branch_id
        FROM public.orders o
        WHERE o.id = NEW.order_id;
    END IF;

    -- 1. Deduct base menu item recipe ingredients.
    FOR r_recipe IN
        SELECT r.inventory_item_id, r.quantity_required, COALESCE(r.yield_percentage, 100.00) AS yield_percentage
        FROM public.recipes r
        JOIN public.inventory_items ii ON ii.id = r.inventory_item_id
        WHERE r.menu_item_id::text = NEW.item_id
          AND COALESCE(r.is_deleted, FALSE) = FALSE
          AND ii.merchant_id = NEW.merchant_id
          AND COALESCE(ii.is_deleted, FALSE) = FALSE
          AND (v_branch_id IS NULL OR ii.branch_id = v_branch_id)
    LOOP
        SELECT EXISTS (
            SELECT 1
            FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = NEW.id
              AND it.item_id = r_recipe.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        IF NOT v_transaction_exists THEN
            UPDATE public.inventory_items
            SET current_quantity = current_quantity - (r_recipe.quantity_required * (100.00 / r_recipe.yield_percentage) * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE
            WHERE id = r_recipe.inventory_item_id;

            INSERT INTO public.inventory_transactions (
                id, merchant_id, item_id, item_name, transaction_type, type,
                quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
            )
            SELECT
                uuid_generate_v4(), NEW.merchant_id, r_recipe.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                'sell', 'sell', -(r_recipe.quantity_required * (100.00 / r_recipe.yield_percentage) * NEW.quantity),
                NEW.id, 'Auto-deducted base recipe (Yield Adjusted: ' || r_recipe.yield_percentage || '%) for Order Item ID: ' || NEW.id,
                v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM public.inventory_items ii
            WHERE ii.id = r_recipe.inventory_item_id;
        END IF;
    END LOOP;

    -- 2. Deduct selected modifier ingredients.
    FOR r_modifier IN
        SELECT m.inventory_item_id, m.quantity_required, m.name AS modifier_name, oim.id AS oim_id
        FROM public.order_item_modifiers oim
        JOIN public.modifiers m ON oim.modifier_id = m.id
        JOIN public.inventory_items ii ON ii.id = m.inventory_item_id
        WHERE oim.order_item_id = NEW.id
          AND m.inventory_item_id IS NOT NULL
          AND COALESCE(oim.is_deleted, FALSE) = FALSE
          AND COALESCE(m.is_deleted, FALSE) = FALSE
          AND ii.merchant_id = NEW.merchant_id
          AND COALESCE(ii.is_deleted, FALSE) = FALSE
          AND (v_branch_id IS NULL OR ii.branch_id = v_branch_id)
    LOOP
        SELECT EXISTS (
            SELECT 1
            FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = r_modifier.oim_id
              AND it.item_id = r_modifier.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        IF NOT v_transaction_exists THEN
            UPDATE public.inventory_items
            SET current_quantity = current_quantity - (r_modifier.quantity_required * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE
            WHERE id = r_modifier.inventory_item_id;

            INSERT INTO public.inventory_transactions (
                id, merchant_id, item_id, item_name, transaction_type, type,
                quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
            )
            SELECT
                uuid_generate_v4(), NEW.merchant_id, r_modifier.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                'sell', 'sell', -(r_modifier.quantity_required * NEW.quantity),
                r_modifier.oim_id, 'Auto-deducted modifier (' || r_modifier.modifier_name || ')',
                v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM public.inventory_items ii
            WHERE ii.id = r_modifier.inventory_item_id;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deduct_stock_on_order_item ON public.order_items;
CREATE TRIGGER trg_deduct_stock_on_order_item
AFTER INSERT OR UPDATE OF status ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.deduct_stock_on_order_item_event();

-- =========================================================================
-- TRIGGER 2: Auto-Onboard Merchant on Auth Sign-Up
-- =========================================================================

CREATE OR REPLACE FUNCTION public.handle_new_merchant_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merchant_id UUID;
    v_first_name TEXT;
    v_last_name TEXT;
BEGIN
    SELECT id INTO v_merchant_id
    FROM public.merchants
    WHERE LOWER(email) = LOWER(new.email)
    LIMIT 1;

    IF v_merchant_id IS NULL THEN
        INSERT INTO public.merchants (name, email)
        VALUES (
            COALESCE(new.raw_user_meta_data->>'store_name', 'My New POS Shop'),
            new.email
        )
        RETURNING id INTO v_merchant_id;
    END IF;

    v_first_name := COALESCE(new.raw_user_meta_data->>'first_name', 'Owner');
    v_last_name := COALESCE(new.raw_user_meta_data->>'last_name', 'User');

    INSERT INTO public.merchant_users (id, merchant_id, first_name, last_name, role)
    VALUES (new.id, v_merchant_id, v_first_name, v_last_name, 'owner')
    ON CONFLICT (id) DO UPDATE
    SET merchant_id = EXCLUDED.merchant_id,
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        role = EXCLUDED.role;

    UPDATE auth.users
    SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('merchant_id', v_merchant_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_merchant_user();

-- =========================================================================
-- TRIGGER 3: Auto-Sync restaurant_tables.status on Session Change
-- =========================================================================

CREATE OR REPLACE FUNCTION sync_table_status_on_session_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.is_active = 1 THEN
        UPDATE restaurant_tables
        SET status = 'occupied', updated_at = NOW()
        WHERE table_number = NEW.table_number AND merchant_id = NEW.merchant_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.is_active = 0 AND OLD.is_active = 1 THEN
        UPDATE restaurant_tables
        SET status = 'vacant', updated_at = NOW()
        WHERE table_number = NEW.table_number AND merchant_id = NEW.merchant_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_table_status ON table_sessions;
CREATE TRIGGER trg_sync_table_status
AFTER INSERT OR UPDATE OF is_active ON table_sessions
FOR EACH ROW
EXECUTE FUNCTION sync_table_status_on_session_change();

-- =========================================================================
-- TRIGGER 4: Revert Stock on Void or Cancel Event
-- =========================================================================

CREATE OR REPLACE FUNCTION public.revert_stock_on_void_or_cancel_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    r_recipe RECORD;
    r_modifier RECORD;
    v_branch_id UUID;
    v_transaction_exists BOOLEAN;
    v_void_logged BOOLEAN;
BEGIN
    -- Only trigger when status is updated to 'cancelled' from 'cooking' or 'served'
    -- (meaning the stock was already deducted)
    IF NOT (
        NEW.status = 'cancelled'
        AND (OLD.status = 'cooking' OR OLD.status = 'served')
    ) THEN
        RETURN NEW;
    END IF;

    v_branch_id := NEW.branch_id;
    IF v_branch_id IS NULL THEN
        SELECT o.branch_id INTO v_branch_id FROM public.orders o WHERE o.id = NEW.order_id;
    END IF;

    -- 1. Revert base menu item recipe ingredients
    FOR r_recipe IN
        SELECT r.inventory_item_id, r.quantity_required, COALESCE(r.yield_percentage, 100.00) AS yield_percentage
        FROM public.recipes r
        JOIN public.inventory_items ii ON ii.id = r.inventory_item_id
        WHERE r.menu_item_id::text = NEW.item_id
          AND COALESCE(r.is_deleted, FALSE) = FALSE
          AND ii.merchant_id = NEW.merchant_id
          AND COALESCE(ii.is_deleted, FALSE) = FALSE
          AND (v_branch_id IS NULL OR ii.branch_id = v_branch_id)
    LOOP
        -- Check if a deduction transaction exists for this item
        SELECT EXISTS (
            SELECT 1 FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = NEW.id
              AND it.item_id = r_recipe.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        -- Only revert if it was deducted and not yet voided/reverted
        IF v_transaction_exists THEN
            SELECT EXISTS (
                SELECT 1 FROM public.inventory_transactions it
                WHERE it.merchant_id = NEW.merchant_id
                  AND it.transaction_type = 'void'
                  AND it.reference_id = NEW.id
                  AND it.item_id = r_recipe.inventory_item_id
                  AND COALESCE(it.is_deleted, FALSE) = FALSE
            ) INTO v_void_logged;

            IF NOT v_void_logged THEN
                -- Restore stock quantity
                UPDATE public.inventory_items
                SET current_quantity = current_quantity + (r_recipe.quantity_required * (100.00 / r_recipe.yield_percentage) * NEW.quantity),
                    updated_at = CURRENT_TIMESTAMP,
                    is_synced = FALSE
                WHERE id = r_recipe.inventory_item_id;

                -- Log void transaction for Audit Trail
                INSERT INTO public.inventory_transactions (
                    id, merchant_id, item_id, item_name, transaction_type, type,
                    quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
                )
                SELECT
                    uuid_generate_v4(), NEW.merchant_id, r_recipe.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                    'void', 'void', (r_recipe.quantity_required * (100.00 / r_recipe.yield_percentage) * NEW.quantity),
                    NEW.id, 'Stock restored (Yield Adjusted: ' || r_recipe.yield_percentage || '%) due to Void/Cancel of Order Item ID: ' || NEW.id,
                    v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM public.inventory_items ii
                WHERE ii.id = r_recipe.inventory_item_id;
            END IF;
        END IF;
    END LOOP;

    -- 2. Revert selected modifier ingredients
    FOR r_modifier IN
        SELECT m.inventory_item_id, m.quantity_required, m.name AS modifier_name, oim.id AS oim_id
        FROM public.order_item_modifiers oim
        JOIN public.modifiers m ON oim.modifier_id = m.id
        JOIN public.inventory_items ii ON ii.id = m.inventory_item_id
        WHERE oim.order_item_id = NEW.id
          AND m.inventory_item_id IS NOT NULL
          AND COALESCE(oim.is_deleted, FALSE) = FALSE
          AND COALESCE(m.is_deleted, FALSE) = FALSE
          AND ii.merchant_id = NEW.merchant_id
          AND COALESCE(ii.is_deleted, FALSE) = FALSE
          AND (v_branch_id IS NULL OR ii.branch_id = v_branch_id)
    LOOP
        -- Check if modifier deduction exists
        SELECT EXISTS (
            SELECT 1 FROM public.inventory_transactions it
            WHERE it.merchant_id = NEW.merchant_id
              AND it.transaction_type = 'sell'
              AND it.reference_id = r_modifier.oim_id
              AND it.item_id = r_modifier.inventory_item_id
              AND COALESCE(it.is_deleted, FALSE) = FALSE
        ) INTO v_transaction_exists;

        IF v_transaction_exists THEN
            SELECT EXISTS (
                SELECT 1 FROM public.inventory_transactions it
                WHERE it.merchant_id = NEW.merchant_id
                  AND it.transaction_type = 'void'
                  AND it.reference_id = r_modifier.oim_id
                  AND it.item_id = r_modifier.inventory_item_id
                  AND COALESCE(it.is_deleted, FALSE) = FALSE
            ) INTO v_void_logged;

            IF NOT v_void_logged THEN
                -- Restore stock quantity
                UPDATE public.inventory_items
                SET current_quantity = current_quantity + (r_modifier.quantity_required * NEW.quantity),
                    updated_at = CURRENT_TIMESTAMP,
                    is_synced = FALSE
                WHERE id = r_modifier.inventory_item_id;

                -- Log void transaction for Audit Trail
                INSERT INTO public.inventory_transactions (
                    id, merchant_id, item_id, item_name, transaction_type, type,
                    quantity, reference_id, notes, branch_id, is_synced, is_deleted, updated_at, created_at
                )
                SELECT
                    uuid_generate_v4(), NEW.merchant_id, r_modifier.inventory_item_id, COALESCE(ii.name, NEW.item_name),
                    'void', 'void', (r_modifier.quantity_required * NEW.quantity),
                    r_modifier.oim_id, 'Stock restored due to Void/Cancel of modifier (' || r_modifier.modifier_name || ')',
                    v_branch_id, FALSE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM public.inventory_items ii
                WHERE ii.id = r_modifier.inventory_item_id;
            END IF;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_revert_stock_on_void ON public.order_items;
CREATE TRIGGER trg_revert_stock_on_void
AFTER UPDATE OF status ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.revert_stock_on_void_or_cancel_event();
