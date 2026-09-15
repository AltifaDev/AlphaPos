BEGIN;

WITH ranked AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY merchant_id, branch_id, employee_id
               ORDER BY clock_in ASC, id ASC
           ) AS position
    FROM public.timecards
    WHERE clock_out IS NULL
      AND branch_id IS NOT NULL
)
UPDATE public.timecards AS timecard
SET clock_out = timecard.clock_in,
    status = 'rejected',
    notes = concat_ws(' · ', nullif(timecard.notes, ''), 'Duplicate open timecard closed by integrity repair'),
    updated_at = now()
FROM ranked
WHERE timecard.id = ranked.id
  AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS timecards_one_open_per_employee_branch_uidx
    ON public.timecards (merchant_id, branch_id, employee_id)
    WHERE clock_out IS NULL AND branch_id IS NOT NULL;

COMMIT;
