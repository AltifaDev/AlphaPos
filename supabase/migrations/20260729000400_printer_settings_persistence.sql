BEGIN;

ALTER TABLE public.printers
    ADD COLUMN IF NOT EXISTS emulation TEXT NOT NULL DEFAULT 'escpos';

WITH ranked AS (
    SELECT id, row_number() OVER (
        PARTITION BY merchant_id, lower(btrim(name)), connection_type,
                     COALESCE(ip_address, ''), COALESCE(port, 9100),
                     COALESCE(bluetooth_name, ''), paper_width, role
        ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id
    ) AS rn
    FROM public.printers
    WHERE COALESCE(is_deleted, FALSE) = FALSE
)
UPDATE public.printers p
SET is_deleted = TRUE, updated_at = now()
FROM ranked r
WHERE p.id = r.id AND r.rn > 1;

COMMIT;
