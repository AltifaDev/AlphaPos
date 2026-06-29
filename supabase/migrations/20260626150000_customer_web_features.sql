-- =========================================================================
-- Migration: Customer Web App Features
-- Created: 2026-06-26
-- Description: Adds tables for Customer Feedback, Allergen/Dietary Info,
--              Estimated Wait Time, and Loyalty Points.
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. CUSTOMER FEEDBACK / RATINGS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.customer_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    table_number VARCHAR(10),
    session_token VARCHAR(255),
    overall_rating INTEGER NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),
    food_rating INTEGER CHECK (food_rating BETWEEN 1 AND 5),
    service_rating INTEGER CHECK (service_rating BETWEEN 1 AND 5),
    ambience_rating INTEGER CHECK (ambience_rating BETWEEN 1 AND 5),
    comment TEXT,
    customer_name VARCHAR(100),
    customer_email VARCHAR(255),
    tags TEXT[], -- e.g. {'fast_service', 'great_food', 'friendly_staff'}
    is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    resolved_at TIMESTAMP WITH TIME ZONE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.customer_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_customer_feedback" ON public.customer_feedback
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_customer_feedback_merchant
    ON public.customer_feedback (merchant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customer_feedback_order
    ON public.customer_feedback (order_id);
CREATE INDEX IF NOT EXISTS idx_customer_feedback_rating
    ON public.customer_feedback (merchant_id, overall_rating, created_at DESC);


-- =========================================================================
-- 2. ALLERGEN & DIETARY TAGS
-- =========================================================================

-- Master allergen list (per merchant, customizable)
CREATE TABLE IF NOT EXISTS public.allergen_tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    code VARCHAR(30) NOT NULL, -- 'gluten', 'dairy', 'nuts', 'shellfish', 'eggs', 'soy', 'fish', 'sesame'
    name_en VARCHAR(50) NOT NULL,
    name_th VARCHAR(50),
    name_zh VARCHAR(50),
    icon VARCHAR(10), -- emoji icon
    severity VARCHAR(20) DEFAULT 'warning', -- 'warning', 'danger', 'info'
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_merchant_allergen_code UNIQUE (merchant_id, code)
);

ALTER TABLE public.allergen_tags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_allergen_tags" ON public.allergen_tags
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_allergen_tags_merchant
    ON public.allergen_tags (merchant_id, is_active, sort_order);

-- Many-to-many: menu items ↔ allergens
CREATE TABLE IF NOT EXISTS public.menu_item_allergens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    menu_item_id TEXT REFERENCES menu_items(id) ON DELETE CASCADE NOT NULL,
    allergen_id UUID REFERENCES allergen_tags(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_item_allergen UNIQUE (menu_item_id, allergen_id)
);

ALTER TABLE public.menu_item_allergens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_menu_item_allergens" ON public.menu_item_allergens
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_menu_item_allergens_item
    ON public.menu_item_allergens (menu_item_id);
CREATE INDEX IF NOT EXISTS idx_menu_item_allergens_allergen
    ON public.menu_item_allergens (allergen_id);

-- Add dietary columns to menu_items
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS is_vegetarian BOOLEAN DEFAULT FALSE;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS is_vegan BOOLEAN DEFAULT FALSE;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS is_halal BOOLEAN DEFAULT FALSE;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS is_gluten_free BOOLEAN DEFAULT FALSE;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS spice_level INTEGER DEFAULT 0 CHECK (spice_level BETWEEN 0 AND 5);
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS calories INTEGER;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS prep_time_minutes INTEGER; -- used for wait time estimation


-- =========================================================================
-- 3. ESTIMATED WAIT TIME TRACKING
-- =========================================================================

-- Track kitchen prep time per item for estimation accuracy
CREATE TABLE IF NOT EXISTS public.prep_time_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    menu_item_id TEXT REFERENCES menu_items(id) ON DELETE SET NULL,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER, -- calculated on completion
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE public.prep_time_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_prep_time_logs" ON public.prep_time_logs
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_prep_time_logs_merchant
    ON public.prep_time_logs (merchant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prep_time_logs_item
    ON public.prep_time_logs (menu_item_id, completed_at DESC);


-- =========================================================================
-- 4. RPC: get_estimated_wait_time
-- Returns estimated minutes based on:
--   - Number of orders ahead in queue
--   - Average prep time per item (from historical data)
--   - Current kitchen load
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_estimated_wait_time(p_merchant_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_orders_ahead INTEGER;
    v_avg_prep_time NUMERIC;
    v_items_in_queue INTEGER;
    v_estimated_minutes INTEGER;
BEGIN
    -- Count orders currently preparing
    SELECT COUNT(*) INTO v_orders_ahead
    FROM orders
    WHERE merchant_id = p_merchant_id
      AND status IN ('preparing', 'confirmed')
      AND created_at > CURRENT_TIMESTAMP - INTERVAL '4 hours';

    -- Count items in kitchen queue
    SELECT COALESCE(SUM(oi.quantity), 0) INTO v_items_in_queue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.merchant_id = p_merchant_id
      AND oi.status IN ('cooking', 'pending')
      AND o.created_at > CURRENT_TIMESTAMP - INTERVAL '4 hours';

    -- Get average prep time (from last 100 completed orders)
    SELECT COALESCE(AVG(duration_seconds) / 60.0, 12) INTO v_avg_prep_time
    FROM (
        SELECT duration_seconds
        FROM prep_time_logs
        WHERE merchant_id = p_merchant_id
          AND completed_at IS NOT NULL
          AND created_at > CURRENT_TIMESTAMP - INTERVAL '7 days'
        ORDER BY created_at DESC
        LIMIT 100
    ) recent;

    -- Estimate: (orders_ahead * avg_prep) + buffer
    -- Simplified: items_in_queue * avg_per_item_time
    v_estimated_minutes := GREATEST(5, LEAST(90,
        CEIL(v_items_in_queue * v_avg_prep_time / GREATEST(1, LEAST(v_orders_ahead, 5)))
    ));

    RETURN jsonb_build_object(
        'estimated_minutes', v_estimated_minutes,
        'orders_ahead', v_orders_ahead,
        'items_in_queue', v_items_in_queue,
        'avg_prep_time_minutes', ROUND(v_avg_prep_time::numeric, 1),
        'calculated_at', CURRENT_TIMESTAMP
    );
END;
$$ LANGUAGE plpgsql STABLE;


-- =========================================================================
-- 5. RPC: get_feedback_summary (for merchant dashboard)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_feedback_summary(p_merchant_id UUID, p_days INTEGER DEFAULT 30)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_reviews', COUNT(*),
        'avg_overall', ROUND(AVG(overall_rating)::numeric, 1),
        'avg_food', ROUND(AVG(food_rating)::numeric, 1),
        'avg_service', ROUND(AVG(service_rating)::numeric, 1),
        'avg_ambience', ROUND(AVG(ambience_rating)::numeric, 1),
        'rating_distribution', jsonb_build_object(
            '5', COUNT(*) FILTER (WHERE overall_rating = 5),
            '4', COUNT(*) FILTER (WHERE overall_rating = 4),
            '3', COUNT(*) FILTER (WHERE overall_rating = 3),
            '2', COUNT(*) FILTER (WHERE overall_rating = 2),
            '1', COUNT(*) FILTER (WHERE overall_rating = 1)
        ),
        'period_days', p_days
    ) INTO v_result
    FROM customer_feedback
    WHERE merchant_id = p_merchant_id
      AND is_deleted = FALSE
      AND created_at > CURRENT_TIMESTAMP - (p_days || ' days')::interval;

    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql STABLE;


-- =========================================================================
-- 6. SEED DEFAULT ALLERGENS (for all merchants)
-- =========================================================================

-- Note: In production, run per merchant_id. This creates a template set.
-- Application code should copy these to merchant on first setup.

CREATE TABLE IF NOT EXISTS public.allergen_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(30) NOT NULL UNIQUE,
    name_en VARCHAR(50) NOT NULL,
    name_th VARCHAR(50),
    name_zh VARCHAR(50),
    icon VARCHAR(10),
    severity VARCHAR(20) DEFAULT 'warning',
    sort_order INTEGER NOT NULL DEFAULT 0
);

INSERT INTO public.allergen_templates (code, name_en, name_th, name_zh, icon, severity, sort_order) VALUES
    ('gluten', 'Gluten', 'กลูเตน', '麸质', '🌾', 'warning', 1),
    ('dairy', 'Dairy', 'นม', '乳制品', '🥛', 'warning', 2),
    ('eggs', 'Eggs', 'ไข่', '鸡蛋', '🥚', 'warning', 3),
    ('nuts', 'Tree Nuts', 'ถั่วเปลือกแข็ง', '坚果', '🥜', 'danger', 4),
    ('peanuts', 'Peanuts', 'ถั่วลิสง', '花生', '🥜', 'danger', 5),
    ('shellfish', 'Shellfish', 'หอย/กุ้ง', '贝类', '🦐', 'danger', 6),
    ('fish', 'Fish', 'ปลา', '鱼', '🐟', 'warning', 7),
    ('soy', 'Soy', 'ถั่วเหลือง', '大豆', '🫘', 'warning', 8),
    ('sesame', 'Sesame', 'งา', '芝麻', '⚪', 'warning', 9),
    ('celery', 'Celery', 'ขึ้นฉ่าย', '芹菜', '🥬', 'info', 10),
    ('mustard', 'Mustard', 'มัสตาร์ด', '芥末', '🟡', 'info', 11),
    ('sulfites', 'Sulfites', 'ซัลไฟต์', '亚硫酸盐', '🧪', 'info', 12)
ON CONFLICT (code) DO NOTHING;


-- =========================================================================
-- 7. GRANTS
-- =========================================================================

GRANT SELECT, INSERT ON public.customer_feedback TO anon;
GRANT SELECT, INSERT ON public.customer_feedback TO authenticated;
GRANT SELECT ON public.allergen_tags TO anon;
GRANT SELECT ON public.allergen_tags TO authenticated;
GRANT ALL ON public.allergen_tags TO service_role;
GRANT SELECT ON public.menu_item_allergens TO anon;
GRANT SELECT ON public.menu_item_allergens TO authenticated;
GRANT ALL ON public.menu_item_allergens TO service_role;
GRANT SELECT ON public.allergen_templates TO anon;
GRANT SELECT ON public.allergen_templates TO authenticated;
GRANT SELECT, INSERT ON public.prep_time_logs TO anon;
GRANT SELECT, INSERT ON public.prep_time_logs TO authenticated;
GRANT ALL ON public.prep_time_logs TO service_role;
GRANT EXECUTE ON FUNCTION public.get_estimated_wait_time(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_estimated_wait_time(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_feedback_summary(UUID, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_feedback_summary(UUID, INTEGER) TO authenticated;


-- =========================================================================
-- 8. REALTIME PUBLICATION
-- =========================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE customer_feedback;


COMMIT;
