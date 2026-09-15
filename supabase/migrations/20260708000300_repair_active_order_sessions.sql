-- Repair and guard against table flicker caused by orders that still have an
-- active session_token while table_sessions is missing.

INSERT INTO public.table_sessions (
    id,
    merchant_id,
    table_number,
    session_token,
    is_active,
    guest_count,
    created_at,
    ended_at
)
SELECT
    gen_random_uuid(),
    o.merchant_id,
    o.table_number,
    o.session_token,
    1,
    COALESCE(MAX(o.guest_count), 1),
    MIN(o.created_at),
    NULL
FROM public.orders o
WHERE NULLIF(o.session_token, '') IS NOT NULL
  AND COALESCE(o.is_deleted, false) = false
  AND o.status NOT IN ('completed', 'cancelled', 'served')
  AND NOT EXISTS (
      SELECT 1
      FROM public.table_sessions ts
      WHERE ts.merchant_id = o.merchant_id
        AND ts.session_token = o.session_token
        AND ts.is_active = 1
  )
GROUP BY o.merchant_id, o.table_number, o.session_token
ON CONFLICT (session_token) DO UPDATE
SET is_active = 1,
    ended_at = NULL,
    table_number = EXCLUDED.table_number,
    guest_count = EXCLUDED.guest_count;

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
