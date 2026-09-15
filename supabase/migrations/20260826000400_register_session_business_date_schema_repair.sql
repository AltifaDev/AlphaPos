BEGIN;

-- Idempotent repair for self-hosted installations that received the newer
-- client before 20260823000200_business_date_shift_accounting.sql was applied.
ALTER TABLE public.branches
    ADD COLUMN IF NOT EXISTS business_day_cutoff_hour SMALLINT NOT NULL DEFAULT 4,
    ADD COLUMN IF NOT EXISTS time_zone_id TEXT NOT NULL DEFAULT 'Asia/Bangkok';

ALTER TABLE public.register_sessions
    ADD COLUMN IF NOT EXISTS business_date DATE;

UPDATE public.register_sessions AS session
SET business_date = (
    session.opened_at AT TIME ZONE COALESCE(branch.time_zone_id, 'Asia/Bangkok')
    - make_interval(hours => COALESCE(branch.business_day_cutoff_hour, 4))
)::DATE
FROM public.branches AS branch
WHERE branch.id = session.branch_id
  AND session.business_date IS NULL;

CREATE INDEX IF NOT EXISTS register_sessions_business_date_idx
    ON public.register_sessions (merchant_id, branch_id, business_date);

-- Ask PostgREST to refresh immediately after the DDL transaction commits.
NOTIFY pgrst, 'reload schema';

COMMIT;
