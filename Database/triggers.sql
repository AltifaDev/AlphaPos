-- PostgreSQL Triggers for AlphaPos Stock Inventory Consumption

-- =========================================================================
-- TRIGGER: Auto-Deduct Inventory on Cooking / Serving of Order Items
-- =========================================================================

CREATE OR REPLACE FUNCTION deduct_stock_on_order_item_event()
RETURNS TRIGGER AS $$
DECLARE
    r_recipe RECORD;
    r_modifier RECORD;
BEGIN
    -- Only trigger stock deduction when transitions to 'cooking' or 'served'
    -- (This matches our direct-to-kitchen QR order setup where status starts as 'cooking')
    IF (NEW.status = 'cooking' OR NEW.status = 'served') AND (OLD.status IS NULL OR OLD.status = 'pending') THEN
        
        -- 1. DEDUCT BASE MENU ITEM RECIPE INGREDIENTS
        FOR r_recipe IN 
            SELECT inventory_item_id, quantity_required 
            FROM recipes 
            WHERE menu_item_id = NEW.item_id::UUID
        LOOP
            -- Deduct stock in inventory
            UPDATE inventory_items
            SET current_quantity = current_quantity - (r_recipe.quantity_required * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE -- Queue for syncing to client apps
            WHERE id = r_recipe.inventory_item_id;
            
            -- Insert inventory transaction record for audit logging
            INSERT INTO inventory_transactions (
                item_id, 
                transaction_type, 
                quantity, 
                reference_id, 
                notes,
                is_synced
            ) VALUES (
                r_recipe.inventory_item_id,
                'sell',
                -(r_recipe.quantity_required * NEW.quantity),
                NEW.id,
                'Auto-deducted base recipe for Order Item ID: ' || NEW.id || ' (Qty: ' || NEW.quantity || ')',
                FALSE
            );
        END LOOP;
        
        -- 2. DEDUCT CUSTOM MODIFIER INGREDIENTS
        -- Fetch all modifiers selected for this specific order item
        FOR r_modifier IN 
            SELECT m.inventory_item_id, m.quantity_required, m.name as modifier_name, oim.id as oim_id
            FROM order_item_modifiers oim
            JOIN modifiers m ON oim.modifier_id = m.id
            WHERE oim.order_item_id = NEW.id
              AND m.inventory_item_id IS NOT NULL -- Only modifiers linked to inventory items
        LOOP
            -- Deduct stock in inventory
            UPDATE inventory_items
            SET current_quantity = current_quantity - (r_modifier.quantity_required * NEW.quantity),
                updated_at = CURRENT_TIMESTAMP,
                is_synced = FALSE
            WHERE id = r_modifier.inventory_item_id;
            
            -- Insert transaction record for modifier stock audit logging
            INSERT INTO inventory_transactions (
                item_id, 
                transaction_type, 
                quantity, 
                reference_id, 
                notes,
                is_synced
            ) VALUES (
                r_modifier.inventory_item_id,
                'sell',
                -(r_modifier.quantity_required * NEW.quantity),
                r_modifier.oim_id,
                'Auto-deducted modifier (' || r_modifier.modifier_name || ') for Order Item ID: ' || NEW.id || ' (Qty: ' || NEW.quantity || ')',
                FALSE
            );
        END LOOP;

    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Register trigger on order_items table
DROP TRIGGER IF EXISTS trg_deduct_stock_on_order_item ON order_items;
CREATE TRIGGER trg_deduct_stock_on_order_item
AFTER INSERT OR UPDATE OF status ON order_items
FOR EACH ROW
EXECUTE FUNCTION deduct_stock_on_order_item_event();

-- =========================================================================
-- TRIGGER: Auto-Onboard Merchant on Auth Sign-Up
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
    -- A. Create a new merchant profile for the registering owner
    INSERT INTO public.merchants (name, email)
    VALUES (
        COALESCE(new.raw_user_meta_data->>'store_name', 'My New POS Shop'),
        new.email
    )
    RETURNING id INTO v_merchant_id;

    -- B. Extract owner name from user metadata
    v_first_name := COALESCE(new.raw_user_meta_data->>'first_name', 'Owner');
    v_last_name := COALESCE(new.raw_user_meta_data->>'last_name', 'User');

    -- C. Link to merchant_users table (works in AFTER INSERT as auth.users row exists)
    INSERT INTO public.merchant_users (id, merchant_id, first_name, last_name, role)
    VALUES (new.id, v_merchant_id, v_first_name, v_last_name, 'owner');

    -- D. Inject merchant_id custom claim into app_metadata (raw_app_meta_data)
    UPDATE auth.users
    SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('merchant_id', v_merchant_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Bind the trigger to auth.users table as AFTER INSERT
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_merchant_user();


