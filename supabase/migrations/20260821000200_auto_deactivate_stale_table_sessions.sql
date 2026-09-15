-- ==============================================================================
-- Migration: Auto Deactivate Stale Table Sessions
-- Date: 2026-08-21
-- Purpose: Prevent [23505] idx_table_sessions_one_active_per_table violation
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.deactivate_previous_table_sessions()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_active = 1 THEN
        UPDATE public.table_sessions
        SET is_active = 0, ended_at = COALESCE(ended_at, now())
        WHERE merchant_id = NEW.merchant_id
          AND table_number = NEW.table_number
          AND id <> NEW.id
          AND is_active = 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_deactivate_previous_table_sessions ON public.table_sessions;
CREATE TRIGGER trg_deactivate_previous_table_sessions
BEFORE INSERT OR UPDATE OF is_active ON public.table_sessions
FOR EACH ROW
WHEN (NEW.is_active = 1)
EXECUTE FUNCTION public.deactivate_previous_table_sessions();

NOTIFY pgrst, 'reload schema';
