-- ==============================================================================
-- Migration 006: Add Elapsed Time Tracking to Table Sessions
-- Date: 2026-06-11
-- Purpose: Track when each table session started for elapsed time display
-- ==============================================================================

-- ✅ Part A: Add started_at column to table_sessions
ALTER TABLE IF EXISTS public.table_sessions 
ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE DEFAULT now();

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_table_sessions_started_at 
ON public.table_sessions(started_at DESC)
WHERE is_active = true;

-- ✅ Part B: Update trigger to maintain started_at immutability for active sessions
CREATE OR REPLACE FUNCTION public.preserve_table_session_started_at()
RETURNS TRIGGER AS $$
BEGIN
    -- If session is being marked as inactive, preserve the original started_at
    IF OLD.is_active = true AND NEW.is_active = false THEN
        NEW.started_at = OLD.started_at;
    END IF;
    -- Always update updated_at timestamp
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_preserve_table_session_started_at ON public.table_sessions;

CREATE TRIGGER trigger_preserve_table_session_started_at
BEFORE UPDATE ON public.table_sessions
FOR EACH ROW
EXECUTE FUNCTION public.preserve_table_session_started_at();

-- ✅ Part C: Create helper function to calculate elapsed minutes
CREATE OR REPLACE FUNCTION public.get_session_elapsed_minutes(p_started_at TIMESTAMP WITH TIME ZONE)
RETURNS INTEGER AS $$
BEGIN
    RETURN EXTRACT(EPOCH FROM (now() - p_started_at))::INTEGER / 60;
END;
$$ LANGUAGE plpgsql;

-- ✅ Part D: RLS Policy update (if needed)
ALTER TABLE public.table_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "table_sessions_merchant_access" ON public.table_sessions;

CREATE POLICY "table_sessions_merchant_access" 
    ON public.table_sessions
    FOR ALL
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- ==============================================================================
-- End Migration 006
-- ==============================================================================
