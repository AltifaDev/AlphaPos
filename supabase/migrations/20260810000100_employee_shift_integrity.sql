-- Employee scheduling integrity and overlap protection.
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE public.employee_shifts
    DROP CONSTRAINT IF EXISTS employee_shifts_valid_time;

ALTER TABLE public.employee_shifts
    ADD CONSTRAINT employee_shifts_valid_time
    CHECK (scheduled_end > scheduled_start);

ALTER TABLE public.employee_shifts
    DROP CONSTRAINT IF EXISTS employee_shifts_no_overlap;

ALTER TABLE public.employee_shifts
    ADD CONSTRAINT employee_shifts_no_overlap
    EXCLUDE USING gist (
        merchant_id WITH =,
        employee_id WITH =,
        tstzrange(scheduled_start, scheduled_end, '[)') WITH &&
    ) WHERE (is_deleted = false);

CREATE INDEX IF NOT EXISTS idx_employee_shifts_active_schedule
    ON public.employee_shifts (merchant_id, employee_id, scheduled_start, scheduled_end)
    WHERE is_deleted = false;
