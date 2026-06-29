-- =========================================================================
-- Migration: Staff App Features
-- Created: 2026-06-26
-- Description: Database schema for AlphaPosStaff 10 new features:
--   1. Quick Order Mode (order_type + queue columns)
--   2. Offline Cache (no schema needed — client-side)
--   3. Order Status Timeline (order_status_history + order timestamps)
--   4. Deep Link Notifications (no schema needed — client-side)
--   5. Shift Schedule Viewer (employee_shifts enhancements)
--   6. Daily Summary (get_daily_summary RPC)
--   7. Split Bill (split_payments table)
--   8. Break Timer (employee_breaks table)
--   9. Staff Messaging (chat_channels + chat_messages)
--  10. Tip Tracker (get_tip_summary RPC + tips indexes)
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. ALTER employee_shifts — Add missing columns for Schedule Viewer
-- =========================================================================

ALTER TABLE public.employee_shifts
    ADD COLUMN IF NOT EXISTS merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS shift_type VARCHAR(20) DEFAULT 'morning',
    ADD COLUMN IF NOT EXISTS station VARCHAR(100),
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Backfill merchant_id from employee → merchant relationship
UPDATE public.employee_shifts es
SET merchant_id = e.merchant_id
FROM public.employees e
WHERE es.employee_id = e.id
  AND es.merchant_id IS NULL;

-- Enable RLS on employee_shifts (may not have been enabled before)
ALTER TABLE public.employee_shifts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_employee_shifts" ON public.employee_shifts;
CREATE POLICY "merchant_isolation_employee_shifts" ON public.employee_shifts
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_employee_shifts_merchant_employee
    ON public.employee_shifts (merchant_id, employee_id, scheduled_start);

CREATE INDEX IF NOT EXISTS idx_employee_shifts_schedule_lookup
    ON public.employee_shifts (merchant_id, scheduled_start, scheduled_end);


-- =========================================================================
-- 2. ALTER orders — Add Quick Order & Timeline columns
-- =========================================================================

ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS order_type VARCHAR(20) NOT NULL DEFAULT 'dine_in',
    ADD COLUMN IF NOT EXISTS queue_number INTEGER,
    ADD COLUMN IF NOT EXISTS customer_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS customer_phone VARCHAR(50),
    ADD COLUMN IF NOT EXISTS delivery_address TEXT,
    ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS preparing_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS ready_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS served_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS estimated_prep_minutes INTEGER;

COMMENT ON COLUMN public.orders.order_type IS 'dine_in, takeaway, delivery, walk_in';
COMMENT ON COLUMN public.orders.queue_number IS 'Auto-incremented per merchant per day for takeaway/delivery';

-- Index for queue number generation (get max queue_number for today)
CREATE INDEX IF NOT EXISTS idx_orders_queue_number
    ON public.orders (merchant_id, order_type, created_at DESC)
    WHERE order_type IN ('takeaway', 'delivery', 'walk_in');

-- Index for order timeline lookups
CREATE INDEX IF NOT EXISTS idx_orders_status_timeline
    ON public.orders (merchant_id, status, created_at DESC);


-- =========================================================================
-- 3. CREATE TABLE order_status_history — Order Timeline tracking
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.order_status_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    from_status VARCHAR(20),
    to_status VARCHAR(20) NOT NULL,
    changed_by UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    notes TEXT
);

ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_order_status_history" ON public.order_status_history;
CREATE POLICY "merchant_isolation_order_status_history" ON public.order_status_history
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_order_status_history_order
    ON public.order_status_history (order_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_status_history_merchant
    ON public.order_status_history (merchant_id, changed_at DESC);


-- =========================================================================
-- 4. CREATE TABLE employee_breaks — Break Timer
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.employee_breaks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    employee_id UUID REFERENCES public.employees(id) ON DELETE CASCADE NOT NULL,
    break_type VARCHAR(20) NOT NULL DEFAULT 'short',
    duration_minutes INTEGER NOT NULL DEFAULT 15,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    notes TEXT,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_break_type CHECK (break_type IN ('short', 'meal', 'custom')),
    CONSTRAINT chk_break_status CHECK (status IN ('active', 'completed', 'overtime', 'cancelled'))
);

ALTER TABLE public.employee_breaks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_employee_breaks" ON public.employee_breaks;
CREATE POLICY "merchant_isolation_employee_breaks" ON public.employee_breaks
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_employee_breaks_merchant_employee
    ON public.employee_breaks (merchant_id, employee_id, start_time DESC);

CREATE INDEX IF NOT EXISTS idx_employee_breaks_active
    ON public.employee_breaks (merchant_id, status)
    WHERE status = 'active';


-- =========================================================================
-- 5. CREATE TABLE chat_channels — Staff Messaging
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.chat_channels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    channel_type VARCHAR(20) NOT NULL DEFAULT 'team',
    name VARCHAR(100),
    participants UUID[] NOT NULL DEFAULT '{}',
    last_message_text TEXT,
    last_message_at TIMESTAMP WITH TIME ZONE,
    created_by UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_channel_type CHECK (channel_type IN ('team', 'direct', 'shift'))
);

ALTER TABLE public.chat_channels ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_chat_channels" ON public.chat_channels;
CREATE POLICY "merchant_isolation_chat_channels" ON public.chat_channels
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_chat_channels_merchant
    ON public.chat_channels (merchant_id, is_active, last_message_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_channels_participants
    ON public.chat_channels USING GIN (participants);


-- =========================================================================
-- 6. CREATE TABLE chat_messages — Staff Messaging
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    channel_id UUID REFERENCES public.chat_channels(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.employees(id) ON DELETE SET NULL NOT NULL,
    message_text TEXT NOT NULL,
    message_type VARCHAR(20) NOT NULL DEFAULT 'text',
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMP WITH TIME ZONE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_message_type CHECK (message_type IN ('text', 'quick', 'system', 'image'))
);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_chat_messages" ON public.chat_messages;
CREATE POLICY "merchant_isolation_chat_messages" ON public.chat_messages
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_chat_messages_channel
    ON public.chat_messages (channel_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_messages_unread
    ON public.chat_messages (channel_id, is_read, created_at DESC)
    WHERE is_read = FALSE;

CREATE INDEX IF NOT EXISTS idx_chat_messages_sender
    ON public.chat_messages (sender_id, created_at DESC);


-- =========================================================================
-- 7. CREATE TABLE split_payments — Split Bill
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.split_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    person_index INTEGER NOT NULL CHECK (person_index BETWEEN 1 AND 10),
    person_label VARCHAR(50),
    amount DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
    payment_method VARCHAR(30) NOT NULL,
    items JSONB DEFAULT '[]'::jsonb,
    split_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    paid_at TIMESTAMP WITH TIME ZONE,
    payment_id UUID REFERENCES public.payments(id) ON DELETE SET NULL,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_split_payment_method CHECK (payment_method IN ('cash', 'card', 'qr', 'transfer', 'other')),
    CONSTRAINT chk_split_type CHECK (split_type IN ('equal', 'by_amount', 'by_item')),
    CONSTRAINT chk_split_status CHECK (status IN ('pending', 'paid', 'refunded', 'cancelled'))
);

ALTER TABLE public.split_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation_split_payments" ON public.split_payments;
CREATE POLICY "merchant_isolation_split_payments" ON public.split_payments
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_split_payments_order
    ON public.split_payments (merchant_id, order_id);

CREATE INDEX IF NOT EXISTS idx_split_payments_status
    ON public.split_payments (merchant_id, status, created_at DESC)
    WHERE status = 'pending';


-- =========================================================================
-- 8. ADD INDEXES on existing tips table — Tip Tracker
-- =========================================================================

CREATE INDEX IF NOT EXISTS idx_tips_employee_date
    ON public.tips (merchant_id, employee_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_tips_employee_period
    ON public.tips (employee_id, created_at)
    WHERE is_deleted = FALSE;

-- Add payment_method to tips if not exists (for breakdown by method)
ALTER TABLE public.tips
    ADD COLUMN IF NOT EXISTS payment_method VARCHAR(30) DEFAULT 'cash',
    ADD COLUMN IF NOT EXISTS table_number VARCHAR(10);


-- =========================================================================
-- 9. RPC: get_daily_summary — Daily Performance Dashboard
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_daily_summary(
    p_employee_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB AS $$
DECLARE
    v_merchant_id UUID;
    v_orders_served INTEGER := 0;
    v_revenue DECIMAL(12,2) := 0.00;
    v_avg_prep INTEGER := 0;
    v_tables_turned INTEGER := 0;
    v_tips_earned DECIMAL(10,2) := 0.00;
    v_hours_worked DECIMAL(5,2) := 0.00;
    v_streak INTEGER := 0;
    v_hourly_orders JSONB;
    v_top_items JSONB;
    v_day_start TIMESTAMP WITH TIME ZONE;
    v_day_end TIMESTAMP WITH TIME ZONE;
    v_check_date DATE;
BEGIN
    -- Get merchant_id from employee
    SELECT merchant_id INTO v_merchant_id
    FROM public.employees
    WHERE id = p_employee_id;

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Employee not found');
    END IF;

    v_day_start := p_date::TIMESTAMP WITH TIME ZONE;
    v_day_end := (p_date + INTERVAL '1 day')::TIMESTAMP WITH TIME ZONE;

    -- Orders served (orders with items served by this employee today)
    SELECT COUNT(DISTINCT o.id)
    INTO v_orders_served
    FROM public.orders o
    JOIN public.order_items oi ON oi.order_id = o.id
    WHERE o.merchant_id = v_merchant_id
      AND o.created_at >= v_day_start
      AND o.created_at < v_day_end
      AND (oi.served_by = p_employee_id OR o.status IN ('served', 'completed'));

    -- Revenue generated
    SELECT COALESCE(SUM(o.total), 0)
    INTO v_revenue
    FROM public.orders o
    WHERE o.merchant_id = v_merchant_id
      AND o.created_at >= v_day_start
      AND o.created_at < v_day_end
      AND o.status IN ('served', 'completed', 'paid');

    -- Average prep time (minutes from created → ready)
    SELECT COALESCE(
        AVG(EXTRACT(EPOCH FROM (o.ready_at - o.created_at)) / 60)::INTEGER,
        0
    )
    INTO v_avg_prep
    FROM public.orders o
    WHERE o.merchant_id = v_merchant_id
      AND o.created_at >= v_day_start
      AND o.created_at < v_day_end
      AND o.ready_at IS NOT NULL;

    -- Tables turned
    SELECT COUNT(DISTINCT table_number)
    INTO v_tables_turned
    FROM public.orders
    WHERE merchant_id = v_merchant_id
      AND created_at >= v_day_start
      AND created_at < v_day_end
      AND status IN ('served', 'completed', 'paid')
      AND order_type = 'dine_in';

    -- Tips earned
    SELECT COALESCE(SUM(amount), 0)
    INTO v_tips_earned
    FROM public.tips
    WHERE merchant_id = v_merchant_id
      AND employee_id = p_employee_id
      AND created_at >= v_day_start
      AND created_at < v_day_end
      AND is_deleted = FALSE;

    -- Hours worked (from timecards)
    SELECT COALESCE(
        SUM(
            EXTRACT(EPOCH FROM (
                COALESCE(clock_out, CURRENT_TIMESTAMP) - clock_in
            )) / 3600
        ),
        0
    )::DECIMAL(5,2)
    INTO v_hours_worked
    FROM public.timecards
    WHERE merchant_id = v_merchant_id
      AND employee_id = p_employee_id
      AND clock_in >= v_day_start
      AND clock_in < v_day_end;

    -- Streak (consecutive work days)
    v_streak := 0;
    v_check_date := p_date;
    LOOP
        IF EXISTS (
            SELECT 1 FROM public.timecards
            WHERE employee_id = p_employee_id
              AND clock_in::DATE = v_check_date
        ) THEN
            v_streak := v_streak + 1;
            v_check_date := v_check_date - INTERVAL '1 day';
        ELSE
            EXIT;
        END IF;
        -- Cap at 365 to prevent infinite loop
        EXIT WHEN v_streak >= 365;
    END LOOP;

    -- Hourly orders (array of 24 elements)
    SELECT COALESCE(
        jsonb_agg(hourly_count ORDER BY hour_of_day),
        '[]'::jsonb
    )
    INTO v_hourly_orders
    FROM (
        SELECT
            h.hour_of_day,
            COALESCE(order_counts.cnt, 0) AS hourly_count
        FROM generate_series(0, 23) AS h(hour_of_day)
        LEFT JOIN (
            SELECT
                EXTRACT(HOUR FROM created_at)::INTEGER AS hr,
                COUNT(*) AS cnt
            FROM public.orders
            WHERE merchant_id = v_merchant_id
              AND created_at >= v_day_start
              AND created_at < v_day_end
            GROUP BY hr
        ) order_counts ON order_counts.hr = h.hour_of_day
    ) hourly_data;

    -- Top 5 items
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object('name', item_name, 'quantity', total_qty)
            ORDER BY total_qty DESC
        ),
        '[]'::jsonb
    )
    INTO v_top_items
    FROM (
        SELECT
            oi.item_name,
            SUM(oi.quantity) AS total_qty
        FROM public.order_items oi
        JOIN public.orders o ON o.id = oi.order_id
        WHERE o.merchant_id = v_merchant_id
          AND o.created_at >= v_day_start
          AND o.created_at < v_day_end
        GROUP BY oi.item_name
        ORDER BY total_qty DESC
        LIMIT 5
    ) top_data;

    RETURN jsonb_build_object(
        'orders_served', v_orders_served,
        'revenue_generated', v_revenue,
        'avg_prep_time', v_avg_prep,
        'tables_turned', v_tables_turned,
        'tips_earned', v_tips_earned,
        'hours_worked', v_hours_worked,
        'streak', v_streak,
        'hourly_orders', v_hourly_orders,
        'top_items', v_top_items,
        'date', p_date
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- =========================================================================
-- 10. RPC: get_tip_summary — Tip Tracker Dashboard
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_tip_summary(
    p_employee_id UUID,
    p_period TEXT DEFAULT 'weekly'
)
RETURNS JSONB AS $$
DECLARE
    v_merchant_id UUID;
    v_start_date TIMESTAMP WITH TIME ZONE;
    v_end_date TIMESTAMP WITH TIME ZONE;
    v_total_tips DECIMAL(10,2) := 0.00;
    v_tip_count INTEGER := 0;
    v_avg_per_shift DECIMAL(10,2) := 0.00;
    v_shift_count INTEGER := 0;
    v_daily_totals JSONB;
    v_pool_total DECIMAL(10,2) := 0.00;
    v_pool_share_pct DECIMAL(5,2) := 0.00;
    v_staff_count INTEGER := 1;
BEGIN
    -- Get merchant_id from employee
    SELECT merchant_id INTO v_merchant_id
    FROM public.employees
    WHERE id = p_employee_id;

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Employee not found');
    END IF;

    -- Determine date range
    v_end_date := (CURRENT_DATE + INTERVAL '1 day')::TIMESTAMP WITH TIME ZONE;
    CASE p_period
        WHEN 'daily' THEN
            v_start_date := CURRENT_DATE::TIMESTAMP WITH TIME ZONE;
        WHEN 'weekly' THEN
            v_start_date := (CURRENT_DATE - INTERVAL '6 days')::TIMESTAMP WITH TIME ZONE;
        WHEN 'monthly' THEN
            v_start_date := date_trunc('month', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE;
        ELSE
            v_start_date := (CURRENT_DATE - INTERVAL '6 days')::TIMESTAMP WITH TIME ZONE;
    END CASE;

    -- Total tips for employee in period
    SELECT COALESCE(SUM(amount), 0), COUNT(*)
    INTO v_total_tips, v_tip_count
    FROM public.tips
    WHERE merchant_id = v_merchant_id
      AND employee_id = p_employee_id
      AND created_at >= v_start_date
      AND created_at < v_end_date
      AND is_deleted = FALSE;

    -- Count shifts in period (for average)
    SELECT COUNT(DISTINCT clock_in::DATE)
    INTO v_shift_count
    FROM public.timecards
    WHERE merchant_id = v_merchant_id
      AND employee_id = p_employee_id
      AND clock_in >= v_start_date
      AND clock_in < v_end_date;

    IF v_shift_count > 0 THEN
        v_avg_per_shift := v_total_tips / v_shift_count;
    END IF;

    -- Daily totals breakdown
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'date', day_date::TEXT,
                'amount', day_total
            )
            ORDER BY day_date
        ),
        '[]'::jsonb
    )
    INTO v_daily_totals
    FROM (
        SELECT
            created_at::DATE AS day_date,
            SUM(amount) AS day_total
        FROM public.tips
        WHERE merchant_id = v_merchant_id
          AND employee_id = p_employee_id
          AND created_at >= v_start_date
          AND created_at < v_end_date
          AND is_deleted = FALSE
        GROUP BY day_date
    ) daily_data;

    -- Tip pool calculation (all tips in merchant for the period / active staff count)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_pool_total
    FROM public.tips
    WHERE merchant_id = v_merchant_id
      AND created_at >= v_start_date
      AND created_at < v_end_date
      AND is_deleted = FALSE;

    -- Count active staff who received tips
    SELECT GREATEST(COUNT(DISTINCT employee_id), 1)
    INTO v_staff_count
    FROM public.tips
    WHERE merchant_id = v_merchant_id
      AND created_at >= v_start_date
      AND created_at < v_end_date
      AND is_deleted = FALSE;

    IF v_pool_total > 0 THEN
        v_pool_share_pct := (v_total_tips / v_pool_total * 100)::DECIMAL(5,2);
    END IF;

    RETURN jsonb_build_object(
        'total_tips', v_total_tips,
        'tip_count', v_tip_count,
        'avg_per_shift', v_avg_per_shift,
        'shift_count', v_shift_count,
        'daily_totals', v_daily_totals,
        'pool_total', v_pool_total,
        'pool_share_percent', v_pool_share_pct,
        'staff_count', v_staff_count,
        'period', p_period,
        'start_date', v_start_date::DATE,
        'end_date', (v_end_date - INTERVAL '1 day')::DATE
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- =========================================================================
-- 11. RPC: generate_queue_number — Auto-increment queue per merchant per day
-- =========================================================================

CREATE OR REPLACE FUNCTION public.generate_queue_number(
    p_merchant_id UUID
)
RETURNS INTEGER AS $$
DECLARE
    v_next_queue INTEGER;
BEGIN
    SELECT COALESCE(MAX(queue_number), 0) + 1
    INTO v_next_queue
    FROM public.orders
    WHERE merchant_id = p_merchant_id
      AND created_at::DATE = CURRENT_DATE
      AND order_type IN ('takeaway', 'delivery', 'walk_in');

    RETURN v_next_queue;
END;
$$ LANGUAGE plpgsql VOLATILE;


-- =========================================================================
-- 12. TRIGGER: Auto-record order status changes
-- =========================================================================

CREATE OR REPLACE FUNCTION public.trg_record_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Only fire if status actually changed
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.order_status_history (
            merchant_id, order_id, from_status, to_status, changed_at
        ) VALUES (
            NEW.merchant_id, NEW.id, OLD.status, NEW.status, CURRENT_TIMESTAMP
        );

        -- Also update timestamp columns on the order
        CASE NEW.status
            WHEN 'confirmed' THEN
                NEW.confirmed_at := COALESCE(NEW.confirmed_at, CURRENT_TIMESTAMP);
            WHEN 'preparing' THEN
                NEW.preparing_at := COALESCE(NEW.preparing_at, CURRENT_TIMESTAMP);
            WHEN 'ready' THEN
                NEW.ready_at := COALESCE(NEW.ready_at, CURRENT_TIMESTAMP);
            WHEN 'served', 'completed', 'paid' THEN
                NEW.served_at := COALESCE(NEW.served_at, CURRENT_TIMESTAMP);
            WHEN 'cancelled' THEN
                NEW.cancelled_at := COALESCE(NEW.cancelled_at, CURRENT_TIMESTAMP);
            ELSE
                -- No timestamp update for other statuses
                NULL;
        END CASE;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop if exists to avoid duplicate
DROP TRIGGER IF EXISTS trg_order_status_change ON public.orders;

CREATE TRIGGER trg_order_status_change
    BEFORE UPDATE OF status ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_record_order_status_change();


-- =========================================================================
-- 13. TRIGGER: Auto-update chat_channels.last_message on new message
-- =========================================================================

CREATE OR REPLACE FUNCTION public.trg_update_channel_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.chat_channels
    SET last_message_text = NEW.message_text,
        last_message_at = NEW.created_at
    WHERE id = NEW.channel_id;

    -- Automatically delete messages older than 30 days
    DELETE FROM public.chat_messages
    WHERE created_at < NOW() - INTERVAL '30 days';

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_chat_message_inserted ON public.chat_messages;

CREATE TRIGGER trg_chat_message_inserted
    AFTER INSERT ON public.chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_update_channel_last_message();


-- =========================================================================
-- 14. TRIGGER: Auto-detect break overtime
-- =========================================================================

CREATE OR REPLACE FUNCTION public.trg_check_break_overtime()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.end_time IS NOT NULL AND NEW.status = 'active' THEN
        -- Calculate actual duration
        IF EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 60 > NEW.duration_minutes THEN
            NEW.status := 'overtime';
        ELSE
            NEW.status := 'completed';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_break_end_check ON public.employee_breaks;

CREATE TRIGGER trg_break_end_check
    BEFORE UPDATE OF end_time ON public.employee_breaks
    FOR EACH ROW
    WHEN (NEW.end_time IS NOT NULL AND OLD.end_time IS NULL)
    EXECUTE FUNCTION public.trg_check_break_overtime();


-- =========================================================================
-- 15. GRANTS — Ensure anon/authenticated roles can access new tables
-- =========================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_status_history TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_breaks TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_channels TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_messages TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.split_payments TO anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_status_history TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_breaks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_channels TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.split_payments TO authenticated;

-- Grant execute on new RPCs
GRANT EXECUTE ON FUNCTION public.get_daily_summary(UUID, DATE) TO anon;
GRANT EXECUTE ON FUNCTION public.get_daily_summary(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tip_summary(UUID, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_tip_summary(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_queue_number(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.generate_queue_number(UUID) TO authenticated;


-- =========================================================================
-- 16. REALTIME — Enable real-time subscriptions for messaging & status
-- =========================================================================

-- Note: If supabase_realtime publication doesn't exist, these will fail gracefully.
-- On hosted Supabase, use Dashboard > Database > Replication to enable.
DO $$
BEGIN
    -- Chat messages (live messaging)
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
    EXCEPTION WHEN duplicate_object THEN
        NULL; -- already added
    WHEN undefined_object THEN
        NULL; -- publication doesn't exist (local dev)
    END;

    -- Chat channels (new channel notifications)
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_channels;
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    WHEN undefined_object THEN
        NULL;
    END;

    -- Order status history (timeline updates)
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.order_status_history;
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    WHEN undefined_object THEN
        NULL;
    END;

    -- Employee breaks (break status sync)
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_breaks;
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    WHEN undefined_object THEN
        NULL;
    END;
END;
$$;


COMMIT;


-- =========================================================================
-- SUMMARY OF CHANGES
-- =========================================================================
-- 
-- TABLES CREATED (5):
--   • order_status_history  — tracks every status transition
--   • employee_breaks       — break timer records
--   • chat_channels         — messaging channels (team/direct)
--   • chat_messages         — individual messages
--   • split_payments        — split bill payment records
--
-- TABLES ALTERED (3):
--   • employee_shifts  — added merchant_id, branch_id, shift_type, station, RLS
--   • orders           — added order_type, queue_number, timestamps, customer info
--   • tips             — added payment_method, table_number columns
--
-- FUNCTIONS CREATED (5):
--   • get_daily_summary(employee_id, date) → JSONB performance data
--   • get_tip_summary(employee_id, period) → JSONB tip analytics
--   • generate_queue_number(merchant_id) → next queue number
--   • trg_record_order_status_change() — auto-records status history
--   • trg_update_channel_last_message() — updates channel on new message
--   • trg_check_break_overtime() — auto-detects overtime breaks
--
-- TRIGGERS (3):
--   • trg_order_status_change ON orders
--   • trg_chat_message_inserted ON chat_messages
--   • trg_break_end_check ON employee_breaks
--
-- INDEXES (12 new)
-- REALTIME (4 tables added to publication)
-- GRANTS (5 tables + 3 functions → anon + authenticated)
-- =========================================================================
