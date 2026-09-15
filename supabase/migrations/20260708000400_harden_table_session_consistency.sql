-- Harden offline/online table sync.
-- table_sessions is the source of truth for occupied/vacant table state.

WITH ranked_active_sessions AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id, table_number
            ORDER BY created_at DESC NULLS LAST, id DESC
        ) AS active_rank
    FROM public.table_sessions
    WHERE is_active = 1
)
UPDATE public.table_sessions ts
SET is_active = 0,
    ended_at = COALESCE(ts.ended_at, now())
FROM ranked_active_sessions ranked
WHERE ts.id = ranked.id
  AND ranked.active_rank > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_table_sessions_one_active_per_table
    ON public.table_sessions (merchant_id, table_number)
    WHERE is_active = 1;

CREATE OR REPLACE FUNCTION public.reconcile_restaurant_table_statuses()
RETURNS void AS $$
BEGIN
    UPDATE public.restaurant_tables rt
    SET status = 'occupied',
        updated_at = now()
    WHERE EXISTS (
        SELECT 1
        FROM public.table_sessions ts
        WHERE ts.merchant_id = rt.merchant_id
          AND ts.table_number = rt.table_number
          AND ts.is_active = 1
    )
      AND rt.status <> 'occupied';

    UPDATE public.restaurant_tables rt
    SET status = 'vacant',
        updated_at = now()
    WHERE rt.status = 'occupied'
      AND NOT EXISTS (
          SELECT 1
          FROM public.table_sessions ts
          WHERE ts.merchant_id = rt.merchant_id
            AND ts.table_number = rt.table_number
            AND ts.is_active = 1
      );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.guard_restaurant_table_status_from_sessions()
RETURNS trigger AS $$
BEGIN
    IF NEW.status = 'occupied' AND NOT EXISTS (
        SELECT 1
        FROM public.table_sessions ts
        WHERE ts.merchant_id = NEW.merchant_id
          AND ts.table_number = NEW.table_number
          AND ts.is_active = 1
    ) THEN
        NEW.status := 'vacant';
    ELSIF NEW.status = 'vacant' AND EXISTS (
        SELECT 1
        FROM public.table_sessions ts
        WHERE ts.merchant_id = NEW.merchant_id
          AND ts.table_number = NEW.table_number
          AND ts.is_active = 1
    ) THEN
        NEW.status := 'occupied';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_restaurant_table_status_from_sessions
    ON public.restaurant_tables;

CREATE TRIGGER trg_guard_restaurant_table_status_from_sessions
    BEFORE INSERT OR UPDATE
    ON public.restaurant_tables
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_restaurant_table_status_from_sessions();

SELECT public.reconcile_restaurant_table_statuses();
