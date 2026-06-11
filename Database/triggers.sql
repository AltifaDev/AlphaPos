-- PostgreSQL Triggers for AlphaPos
-- =========================================================================
-- TRIGGER 1: Auto-Deduct Inventory on Cooking / Serving of Order Items
-- =========================================================================

CREATE OR REPLACE FUNCTION deduct_stock_on_order_item_event()
RETURNS TRIGGER AS $$
DECLARE
    r_recipe RECORD;
    r_modifier RECORD;
BEGIN
    IF (NEW.status = 'cooking' OR NEW.status = 'served') AND (OLD.status IS NULL OR OLD.status = 'pending') THEN
        
        -- 1. Deduct base menu item recipe ingredients
        FOR r_recipe IN 
            SELECT inventory_item_id, quantity_required 
            FROM recipes 
            WHERE menu_item_id::text = NEW.item_id
        LOOP
            UPDATE inventory_items
            SET current_quantity = current_quantity - (r_recipe.quantity_required * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE
            WHERE id = r_recipe.inventory_item_id;
            
            INSERT INTO inventory_transactions (
                item_id, transaction_type, quantity, reference_id, notes, is_synced
            ) VALUES (
                r_recipe.inventory_item_id,
                'sell',
                -(r_recipe.quantity_required * NEW.quantity),
                NEW.id,
                'Auto-deducted base recipe for Order Item ID: ' || NEW.id,
                FALSE
            );
        END LOOP;
        
        -- 2. Deduct custom modifier ingredients
        FOR r_modifier IN 
            SELECT m.inventory_item_id, m.quantity_required, m.name as modifier_name, oim.id as oim_id
            FROM order_item_modifiers oim
            JOIN modifiers m ON oim.modifier_id = m.id
            WHERE oim.order_item_id = NEW.id
              AND m.inventory_item_id IS NOT NULL
        LOOP
            UPDATE inventory_items
            SET current_quantity = current_quantity - (r_modifier.quantity_required * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE
            WHERE id = r_modifier.inventory_item_id;
            
            INSERT INTO inventory_transactions (
                item_id, transaction_type, quantity, reference_id, notes, is_synced
            ) VALUES (
                r_modifier.inventory_item_id,
                'sell',
                -(r_modifier.quantity_required * NEW.quantity),
                r_modifier.oim_id,
                'Auto-deducted modifier (' || r_modifier.modifier_name || ')',
                FALSE
            );
        END LOOP;

    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_deduct_stock_on_order_item ON order_items;
CREATE TRIGGER trg_deduct_stock_on_order_item
AFTER INSERT OR UPDATE OF status ON order_items
FOR EACH ROW
EXECUTE FUNCTION deduct_stock_on_order_item_event();

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