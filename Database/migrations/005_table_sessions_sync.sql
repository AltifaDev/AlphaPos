-- ==============================================================================
-- Migration 005: Table Sessions Sync & Guest Count Support
-- Date: 2026-06-11
-- Purpose: Enable guest count sync between iPad (SwiftData) and Web (Supabase)
-- Schema: Adapted for existing table_sessions (uses table_number, not table_id FK)
-- Note: table_sessions already exists; this migration adds missing columns
-- ==============================================================================

-- ✅ Add missing columns to existing table_sessions
ALTER TABLE IF EXISTS public.table_sessions 
    ADD COLUMN IF NOT EXISTS table_id UUID REFERENCES public.restaurant_tables(id);

ALTER TABLE IF EXISTS public.table_sessions 
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT false;

ALTER TABLE IF EXISTS public.table_sessions 
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT false;

ALTER TABLE IF EXISTS public.table_sessions 
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_table_sessions_merchant 
    ON public.table_sessions(merchant_id);
CREATE INDEX IF NOT EXISTS idx_table_sessions_table 
    ON public.table_sessions(table_id);
CREATE INDEX IF NOT EXISTS idx_table_sessions_token
    ON public.table_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_table_sessions_active
    ON public.table_sessions(is_active, merchant_id);

-- ✅ RLS for table_sessions
ALTER TABLE public.table_sessions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'table_sessions' 
        AND policyname = 'table_sessions_merchant_access'
    ) THEN
        CREATE POLICY "table_sessions_merchant_access" 
            ON public.table_sessions
            FOR ALL
            USING (merchant_id = get_active_merchant_id())
            WITH CHECK (merchant_id = get_active_merchant_id());
    END IF;
END $$;

-- ✅ Add columns to orders table
ALTER TABLE IF EXISTS public.orders 
    ADD COLUMN IF NOT EXISTS guest_count INTEGER DEFAULT 1;

ALTER TABLE IF EXISTS public.orders 
    ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT false;

ALTER TABLE IF EXISTS public.orders 
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT false;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'table_session_id'
    ) THEN
        ALTER TABLE public.orders 
            ADD COLUMN table_session_id UUID REFERENCES public.table_sessions(id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_table_session 
    ON public.orders(table_session_id)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_orders_merchant_guest
    ON public.orders(merchant_id, guest_count)
    WHERE is_deleted = false;

-- ✅ RLS for orders
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders;

CREATE POLICY "orders_merchant_access" 
    ON public.orders
    FOR ALL
    USING (
        merchant_id = get_active_merchant_id() 
        OR (is_deleted = false AND table_session_id IS NOT NULL)
    )
    WITH CHECK (merchant_id = get_active_merchant_id());

-- ✅ Trigger for updated_at
CREATE OR REPLACE FUNCTION public.update_table_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_table_sessions_updated_at ON public.table_sessions;

CREATE TRIGGER trigger_table_sessions_updated_at
    BEFORE UPDATE ON public.table_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.update_table_sessions_updated_at();

-- ✅ Function to get guest count
CREATE OR REPLACE FUNCTION public.get_table_guest_count(p_table_id UUID, p_merchant_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_guest_count INTEGER;
BEGIN
    SELECT guest_count INTO v_guest_count
    FROM public.table_sessions
    WHERE table_id = p_table_id 
        AND merchant_id = p_merchant_id
        AND is_active = true
        AND is_deleted = false
    ORDER BY started_at DESC
    LIMIT 1;
    
    RETURN COALESCE(v_guest_count, 1);
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- End Migration 005
-- ==============================================================================
