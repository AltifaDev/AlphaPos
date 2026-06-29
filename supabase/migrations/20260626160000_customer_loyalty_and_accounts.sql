-- =========================================================================
-- Migration: Customer Loyalty, Accounts & Reservations
-- Created: 2026-06-26
-- Description: Adds Customer Accounts (web login), Loyalty Tiers,
--              Loyalty Points ledger, Table Reservations, and RPCs
--              for earning/redeeming loyalty points.
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. CUSTOMER ACCOUNTS (Web self-service login)
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.customer_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(50),
    display_name VARCHAR(100),
    avatar_url TEXT,
    auth_provider VARCHAR(30) NOT NULL DEFAULT 'email', -- email, phone, google, line, facebook
    external_id TEXT, -- provider-specific user ID
    password_hash TEXT, -- bcrypt hash for email/phone login
    points_balance INTEGER NOT NULL DEFAULT 0,
    total_orders INTEGER NOT NULL DEFAULT 0,
    total_spent DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    first_visit_at TIMESTAMP WITH TIME ZONE,
    last_visit_at TIMESTAMP WITH TIME ZONE,
    preferred_language VARCHAR(5) DEFAULT 'th',
    dietary_preferences TEXT[], -- e.g. {'vegetarian', 'halal'}
    allergen_exclusions TEXT[], -- e.g. {'nuts', 'shellfish'}
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_customer_account_email UNIQUE (merchant_id, email),
    CONSTRAINT unique_customer_account_phone UNIQUE (merchant_id, phone)
);

ALTER TABLE public.customer_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_customer_accounts" ON public.customer_accounts
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_customer_accounts_merchant
    ON public.customer_accounts (merchant_id, is_active, is_deleted);
CREATE INDEX IF NOT EXISTS idx_customer_accounts_email
    ON public.customer_accounts (merchant_id, email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customer_accounts_phone
    ON public.customer_accounts (merchant_id, phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customer_accounts_external
    ON public.customer_accounts (merchant_id, auth_provider, external_id) WHERE external_id IS NOT NULL;


-- =========================================================================
-- 2. LOYALTY TIERS (VIP tier definitions per merchant)
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.loyalty_tiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(50) NOT NULL,
    name_th VARCHAR(50),
    name_zh VARCHAR(50),
    min_points INTEGER NOT NULL DEFAULT 0,
    multiplier DECIMAL(3,2) NOT NULL DEFAULT 1.00, -- earning multiplier (1.5x = earn 50% more)
    benefits JSONB DEFAULT '{}'::jsonb, -- {"discount_percent": 5, "free_items": [], "priority_seating": true}
    color VARCHAR(20) DEFAULT '#6B7280',
    icon VARCHAR(10) DEFAULT '⭐',
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_merchant_tier_name UNIQUE (merchant_id, name)
);

ALTER TABLE public.loyalty_tiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_loyalty_tiers" ON public.loyalty_tiers
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_loyalty_tiers_merchant
    ON public.loyalty_tiers (merchant_id, is_active, sort_order);


-- =========================================================================
-- 3. LOYALTY POINTS LEDGER (Detailed earning/redemption log)
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.loyalty_points (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    customer_account_id UUID REFERENCES customer_accounts(id) ON DELETE CASCADE NOT NULL,
    transaction_type VARCHAR(20) NOT NULL, -- earn, redeem, expire, adjust, welcome, referral
    points INTEGER NOT NULL, -- positive = earn, negative = redeem/expire
    balance_after INTEGER NOT NULL,
    source VARCHAR(50), -- order, referral, birthday, manual, promotion, welcome, tier_upgrade
    reference_id UUID, -- FK to orders.id or promotions.id (not enforced for flexibility)
    description TEXT,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.loyalty_points ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_loyalty_points" ON public.loyalty_points
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_loyalty_points_customer
    ON public.loyalty_points (customer_account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_loyalty_points_merchant
    ON public.loyalty_points (merchant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_loyalty_points_expiry
    ON public.loyalty_points (merchant_id, expires_at)
    WHERE expires_at IS NOT NULL AND transaction_type = 'earn';
CREATE INDEX IF NOT EXISTS idx_loyalty_points_source
    ON public.loyalty_points (merchant_id, source, created_at DESC);


-- =========================================================================
-- 4. TABLE RESERVATIONS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.table_reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    customer_account_id UUID REFERENCES customer_accounts(id) ON DELETE SET NULL,
    customer_name VARCHAR(100) NOT NULL,
    customer_phone VARCHAR(50) NOT NULL,
    customer_email VARCHAR(255),
    table_id UUID REFERENCES restaurant_tables(id) ON DELETE SET NULL,
    party_size INTEGER NOT NULL CHECK (party_size > 0 AND party_size <= 50),
    reservation_date DATE NOT NULL,
    reservation_time TIME NOT NULL,
    duration_minutes INTEGER NOT NULL DEFAULT 90 CHECK (duration_minutes > 0 AND duration_minutes <= 480),
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, confirmed, seated, completed, cancelled, no_show
    special_requests TEXT,
    confirmed_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    seated_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    cancelled_reason TEXT,
    reminder_sent BOOLEAN NOT NULL DEFAULT FALSE,
    reminder_sent_at TIMESTAMP WITH TIME ZONE,
    source VARCHAR(30) DEFAULT 'web', -- web, phone, walk_in, third_party
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.table_reservations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_table_reservations" ON public.table_reservations
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_table_reservations_merchant_date
    ON public.table_reservations (merchant_id, reservation_date, reservation_time);
CREATE INDEX IF NOT EXISTS idx_table_reservations_status
    ON public.table_reservations (merchant_id, status, reservation_date);
CREATE INDEX IF NOT EXISTS idx_table_reservations_customer
    ON public.table_reservations (customer_account_id) WHERE customer_account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_table_reservations_table
    ON public.table_reservations (table_id, reservation_date) WHERE table_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_table_reservations_phone
    ON public.table_reservations (merchant_id, customer_phone, reservation_date DESC);


-- =========================================================================
-- 5. ALTER customers — link to customer_accounts
-- =========================================================================

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS customer_account_id UUID REFERENCES customer_accounts(id) ON DELETE SET NULL;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loyalty_tier VARCHAR(50) DEFAULT 'standard';

-- Note: customers.loyalty_points already exists from enterprise_compliance migration


-- =========================================================================
-- 6. ALTER merchants — loyalty program settings
-- =========================================================================

ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS loyalty_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS loyalty_points_per_baht DECIMAL(5,2) NOT NULL DEFAULT 1.00;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS loyalty_redemption_rate DECIMAL(5,2) NOT NULL DEFAULT 0.25;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS loyalty_welcome_bonus INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS loyalty_points_expiry_days INTEGER DEFAULT NULL; -- NULL = never expire
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS reservation_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS reservation_max_party_size INTEGER NOT NULL DEFAULT 20;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS reservation_slot_duration_minutes INTEGER NOT NULL DEFAULT 90;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS reservation_advance_days INTEGER NOT NULL DEFAULT 30; -- how far ahead can book


-- =========================================================================
-- 7. RPC: earn_loyalty_points
-- Called after order payment to award points
-- =========================================================================

CREATE OR REPLACE FUNCTION public.earn_loyalty_points(
    p_merchant_id UUID,
    p_customer_account_id UUID,
    p_order_id UUID,
    p_amount DECIMAL
)
RETURNS JSONB AS $$
DECLARE
    v_points_per_baht DECIMAL;
    v_multiplier DECIMAL;
    v_tier_name VARCHAR;
    v_current_balance INTEGER;
    v_points_earned INTEGER;
    v_new_balance INTEGER;
    v_expiry_days INTEGER;
    v_expires_at TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Get merchant loyalty settings
    SELECT loyalty_points_per_baht, loyalty_points_expiry_days
    INTO v_points_per_baht, v_expiry_days
    FROM merchants
    WHERE id = p_merchant_id;

    IF v_points_per_baht IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Merchant not found');
    END IF;

    -- Get current balance
    SELECT points_balance INTO v_current_balance
    FROM customer_accounts
    WHERE id = p_customer_account_id AND merchant_id = p_merchant_id;

    IF v_current_balance IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Customer account not found');
    END IF;

    -- Get tier multiplier
    SELECT COALESCE(lt.multiplier, 1.00), COALESCE(lt.name, 'standard')
    INTO v_multiplier, v_tier_name
    FROM loyalty_tiers lt
    WHERE lt.merchant_id = p_merchant_id
      AND lt.is_active = TRUE
      AND lt.min_points <= v_current_balance
    ORDER BY lt.min_points DESC
    LIMIT 1;

    IF v_multiplier IS NULL THEN
        v_multiplier := 1.00;
        v_tier_name := 'standard';
    END IF;

    -- Calculate points: amount * points_per_baht * tier_multiplier
    v_points_earned := FLOOR(p_amount * v_points_per_baht * v_multiplier);

    IF v_points_earned <= 0 THEN
        RETURN jsonb_build_object('success', true, 'points_earned', 0, 'balance', v_current_balance);
    END IF;

    v_new_balance := v_current_balance + v_points_earned;

    -- Calculate expiry
    IF v_expiry_days IS NOT NULL THEN
        v_expires_at := CURRENT_TIMESTAMP + (v_expiry_days || ' days')::interval;
    END IF;

    -- Insert ledger entry
    INSERT INTO loyalty_points (
        merchant_id, customer_account_id, transaction_type, points,
        balance_after, source, reference_id, description, expires_at
    ) VALUES (
        p_merchant_id, p_customer_account_id, 'earn', v_points_earned,
        v_new_balance, 'order', p_order_id,
        'Earned from order (x' || v_multiplier || ' ' || v_tier_name || ' tier)',
        v_expires_at
    );

    -- Update customer balance
    UPDATE customer_accounts
    SET points_balance = v_new_balance,
        total_orders = total_orders + 1,
        total_spent = total_spent + p_amount,
        last_visit_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_account_id;

    -- Check for tier upgrade
    PERFORM check_tier_upgrade(p_merchant_id, p_customer_account_id, v_new_balance);

    RETURN jsonb_build_object(
        'success', true,
        'points_earned', v_points_earned,
        'balance', v_new_balance,
        'multiplier', v_multiplier,
        'tier', v_tier_name,
        'expires_at', v_expires_at
    );
END;
$$ LANGUAGE plpgsql;


-- =========================================================================
-- 8. RPC: redeem_loyalty_points
-- Called when customer wants to use points for discount
-- =========================================================================

CREATE OR REPLACE FUNCTION public.redeem_loyalty_points(
    p_merchant_id UUID,
    p_customer_account_id UUID,
    p_points INTEGER,
    p_order_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_current_balance INTEGER;
    v_redemption_rate DECIMAL;
    v_discount_amount DECIMAL;
    v_new_balance INTEGER;
BEGIN
    -- Validate points > 0
    IF p_points <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Points must be positive');
    END IF;

    -- Get merchant redemption rate
    SELECT loyalty_redemption_rate INTO v_redemption_rate
    FROM merchants
    WHERE id = p_merchant_id;

    IF v_redemption_rate IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Merchant not found');
    END IF;

    -- Get current balance
    SELECT points_balance INTO v_current_balance
    FROM customer_accounts
    WHERE id = p_customer_account_id AND merchant_id = p_merchant_id;

    IF v_current_balance IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Customer account not found');
    END IF;

    -- Check sufficient balance
    IF v_current_balance < p_points THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Insufficient points',
            'balance', v_current_balance,
            'requested', p_points
        );
    END IF;

    -- Calculate discount
    v_discount_amount := p_points * v_redemption_rate;
    v_new_balance := v_current_balance - p_points;

    -- Insert redemption ledger entry
    INSERT INTO loyalty_points (
        merchant_id, customer_account_id, transaction_type, points,
        balance_after, source, reference_id, description
    ) VALUES (
        p_merchant_id, p_customer_account_id, 'redeem', -p_points,
        v_new_balance, 'order', p_order_id,
        'Redeemed ' || p_points || ' points for ฿' || v_discount_amount || ' discount'
    );

    -- Update customer balance
    UPDATE customer_accounts
    SET points_balance = v_new_balance,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'points_redeemed', p_points,
        'discount_amount', v_discount_amount,
        'balance', v_new_balance
    );
END;
$$ LANGUAGE plpgsql;


-- =========================================================================
-- 9. RPC: check_tier_upgrade (internal helper)
-- Automatically upgrades customer tier when points threshold reached
-- =========================================================================

CREATE OR REPLACE FUNCTION public.check_tier_upgrade(
    p_merchant_id UUID,
    p_customer_account_id UUID,
    p_current_points INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_new_tier RECORD;
    v_current_tier VARCHAR;
BEGIN
    -- Get the highest tier this customer qualifies for
    SELECT name, min_points, icon
    INTO v_new_tier
    FROM loyalty_tiers
    WHERE merchant_id = p_merchant_id
      AND is_active = TRUE
      AND is_deleted = FALSE
      AND min_points <= p_current_points
    ORDER BY min_points DESC
    LIMIT 1;

    IF v_new_tier IS NULL THEN
        RETURN;
    END IF;

    -- Update customer account (we don't store tier in customer_accounts directly,
    -- tier is always computed from points. But we update the linked customers table if exists)
    UPDATE customers
    SET loyalty_tier = v_new_tier.name,
        loyalty_points = p_current_points
    WHERE customer_account_id = p_customer_account_id
      AND merchant_id = p_merchant_id;
END;
$$ LANGUAGE plpgsql;


-- =========================================================================
-- 10. RPC: get_loyalty_dashboard
-- Returns customer's loyalty status for the web app
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_loyalty_dashboard(
    p_merchant_id UUID,
    p_customer_account_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_account RECORD;
    v_current_tier RECORD;
    v_next_tier RECORD;
    v_recent_transactions JSONB;
    v_merchant RECORD;
BEGIN
    -- Get customer account
    SELECT * INTO v_account
    FROM customer_accounts
    WHERE id = p_customer_account_id AND merchant_id = p_merchant_id;

    IF v_account IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Account not found');
    END IF;

    -- Get merchant settings
    SELECT loyalty_redemption_rate, loyalty_points_per_baht INTO v_merchant
    FROM merchants WHERE id = p_merchant_id;

    -- Get current tier
    SELECT * INTO v_current_tier
    FROM loyalty_tiers
    WHERE merchant_id = p_merchant_id
      AND is_active = TRUE
      AND min_points <= v_account.points_balance
    ORDER BY min_points DESC
    LIMIT 1;

    -- Get next tier (what to aim for)
    SELECT * INTO v_next_tier
    FROM loyalty_tiers
    WHERE merchant_id = p_merchant_id
      AND is_active = TRUE
      AND min_points > v_account.points_balance
    ORDER BY min_points ASC
    LIMIT 1;

    -- Get recent 10 transactions
    SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb)
    INTO v_recent_transactions
    FROM (
        SELECT transaction_type, points, balance_after, source, description, created_at
        FROM loyalty_points
        WHERE customer_account_id = p_customer_account_id
          AND merchant_id = p_merchant_id
        ORDER BY created_at DESC
        LIMIT 10
    ) t;

    RETURN jsonb_build_object(
        'success', true,
        'points_balance', v_account.points_balance,
        'total_orders', v_account.total_orders,
        'total_spent', v_account.total_spent,
        'current_tier', CASE WHEN v_current_tier IS NOT NULL THEN jsonb_build_object(
            'name', v_current_tier.name,
            'icon', v_current_tier.icon,
            'color', v_current_tier.color,
            'multiplier', v_current_tier.multiplier,
            'benefits', v_current_tier.benefits
        ) ELSE NULL END,
        'next_tier', CASE WHEN v_next_tier IS NOT NULL THEN jsonb_build_object(
            'name', v_next_tier.name,
            'icon', v_next_tier.icon,
            'min_points', v_next_tier.min_points,
            'points_needed', v_next_tier.min_points - v_account.points_balance
        ) ELSE NULL END,
        'redemption_rate', v_merchant.loyalty_redemption_rate,
        'points_value', v_account.points_balance * v_merchant.loyalty_redemption_rate,
        'recent_transactions', v_recent_transactions
    );
END;
$$ LANGUAGE plpgsql STABLE;


-- =========================================================================
-- 11. RPC: check_table_availability
-- Returns available time slots for a given date + party size
-- =========================================================================

CREATE OR REPLACE FUNCTION public.check_table_availability(
    p_merchant_id UUID,
    p_date DATE,
    p_party_size INTEGER,
    p_duration_minutes INTEGER DEFAULT 90
)
RETURNS JSONB AS $$
DECLARE
    v_available_tables JSONB;
    v_booked_slots JSONB;
BEGIN
    -- Get tables that can fit the party
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'table_id', rt.id,
        'table_number', rt.table_number,
        'capacity', rt.capacity
    )), '[]'::jsonb)
    INTO v_available_tables
    FROM restaurant_tables rt
    WHERE rt.merchant_id = p_merchant_id
      AND rt.capacity >= p_party_size
      AND rt.is_deleted = FALSE
      AND rt.status != 'maintenance';

    -- Get existing reservations for that date
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'table_id', tr.table_id,
        'time', tr.reservation_time,
        'duration', tr.duration_minutes,
        'party_size', tr.party_size,
        'status', tr.status
    )), '[]'::jsonb)
    INTO v_booked_slots
    FROM table_reservations tr
    WHERE tr.merchant_id = p_merchant_id
      AND tr.reservation_date = p_date
      AND tr.status IN ('pending', 'confirmed', 'seated')
      AND tr.is_deleted = FALSE;

    RETURN jsonb_build_object(
        'date', p_date,
        'party_size', p_party_size,
        'available_tables', v_available_tables,
        'booked_slots', v_booked_slots,
        'total_suitable_tables', jsonb_array_length(v_available_tables)
    );
END;
$$ LANGUAGE plpgsql STABLE;


-- =========================================================================
-- 12. TRIGGER: Auto-update reservation status
-- Marks reservations as 'no_show' if not seated 30 min after time
-- =========================================================================

CREATE OR REPLACE FUNCTION public.trg_reservation_status_update()
RETURNS TRIGGER AS $$
BEGIN
    -- When status changes to 'seated', record timestamp
    IF NEW.status = 'seated' AND OLD.status != 'seated' THEN
        NEW.seated_at := CURRENT_TIMESTAMP;
    END IF;

    -- When status changes to 'cancelled', record timestamp
    IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
        NEW.cancelled_at := CURRENT_TIMESTAMP;
    END IF;

    -- Always update updated_at
    NEW.updated_at := CURRENT_TIMESTAMP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reservation_update
    BEFORE UPDATE ON public.table_reservations
    FOR EACH ROW
    EXECUTE FUNCTION trg_reservation_status_update();


-- =========================================================================
-- 13. TRIGGER: Welcome bonus on account creation
-- =========================================================================

CREATE OR REPLACE FUNCTION public.trg_loyalty_welcome_bonus()
RETURNS TRIGGER AS $$
DECLARE
    v_welcome_bonus INTEGER;
BEGIN
    -- Get merchant's welcome bonus
    SELECT loyalty_welcome_bonus INTO v_welcome_bonus
    FROM merchants
    WHERE id = NEW.merchant_id AND loyalty_enabled = TRUE;

    IF v_welcome_bonus IS NOT NULL AND v_welcome_bonus > 0 THEN
        -- Credit welcome bonus
        NEW.points_balance := v_welcome_bonus;

        -- Insert ledger entry
        INSERT INTO loyalty_points (
            merchant_id, customer_account_id, transaction_type, points,
            balance_after, source, description
        ) VALUES (
            NEW.merchant_id, NEW.id, 'welcome', v_welcome_bonus,
            v_welcome_bonus, 'welcome', 'Welcome bonus for new account'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_customer_account_welcome
    AFTER INSERT ON public.customer_accounts
    FOR EACH ROW
    EXECUTE FUNCTION trg_loyalty_welcome_bonus();


-- =========================================================================
-- 14. SEED DEFAULT LOYALTY TIERS (Template)
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.loyalty_tier_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) NOT NULL UNIQUE,
    name_th VARCHAR(50),
    name_zh VARCHAR(50),
    min_points INTEGER NOT NULL DEFAULT 0,
    multiplier DECIMAL(3,2) NOT NULL DEFAULT 1.00,
    benefits JSONB DEFAULT '{}'::jsonb,
    color VARCHAR(20),
    icon VARCHAR(10),
    sort_order INTEGER NOT NULL DEFAULT 0
);

INSERT INTO public.loyalty_tier_templates (name, name_th, name_zh, min_points, multiplier, benefits, color, icon, sort_order) VALUES
    ('Bronze', 'บรอนซ์', '铜牌', 0, 1.00, '{"discount_percent": 0}', '#CD7F32', '🥉', 1),
    ('Silver', 'ซิลเวอร์', '银牌', 500, 1.25, '{"discount_percent": 3, "priority_seating": false}', '#C0C0C0', '🥈', 2),
    ('Gold', 'โกลด์', '金牌', 2000, 1.50, '{"discount_percent": 5, "priority_seating": true, "free_birthday_dessert": true}', '#FFD700', '🥇', 3),
    ('Platinum', 'แพลทินัม', '白金', 5000, 2.00, '{"discount_percent": 10, "priority_seating": true, "free_birthday_dessert": true, "exclusive_menu": true}', '#E5E4E2', '💎', 4)
ON CONFLICT (name) DO NOTHING;


-- =========================================================================
-- 15. GRANTS
-- =========================================================================

-- customer_accounts: customers can register + read own data
GRANT SELECT, INSERT, UPDATE ON public.customer_accounts TO anon;
GRANT SELECT, INSERT, UPDATE ON public.customer_accounts TO authenticated;
GRANT ALL ON public.customer_accounts TO service_role;

-- loyalty_tiers: read-only for customers
GRANT SELECT ON public.loyalty_tiers TO anon;
GRANT SELECT ON public.loyalty_tiers TO authenticated;
GRANT ALL ON public.loyalty_tiers TO service_role;

-- loyalty_points: read own, system inserts via RPCs
GRANT SELECT ON public.loyalty_points TO anon;
GRANT SELECT ON public.loyalty_points TO authenticated;
GRANT ALL ON public.loyalty_points TO service_role;
GRANT INSERT ON public.loyalty_points TO anon; -- needed for RPCs

-- table_reservations: customers can create + read own
GRANT SELECT, INSERT, UPDATE ON public.table_reservations TO anon;
GRANT SELECT, INSERT, UPDATE ON public.table_reservations TO authenticated;
GRANT ALL ON public.table_reservations TO service_role;

-- loyalty_tier_templates: read-only reference
GRANT SELECT ON public.loyalty_tier_templates TO anon;
GRANT SELECT ON public.loyalty_tier_templates TO authenticated;

-- RPCs
GRANT EXECUTE ON FUNCTION public.earn_loyalty_points(UUID, UUID, UUID, DECIMAL) TO anon;
GRANT EXECUTE ON FUNCTION public.earn_loyalty_points(UUID, UUID, UUID, DECIMAL) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_loyalty_points(UUID, UUID, INTEGER, UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.redeem_loyalty_points(UUID, UUID, INTEGER, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_tier_upgrade(UUID, UUID, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.check_tier_upgrade(UUID, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_loyalty_dashboard(UUID, UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_loyalty_dashboard(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_table_availability(UUID, DATE, INTEGER, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.check_table_availability(UUID, DATE, INTEGER, INTEGER) TO authenticated;


-- =========================================================================
-- 16. REALTIME PUBLICATION
-- =========================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE table_reservations;


COMMIT;
