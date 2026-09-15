-- Make table_session_id the canonical boundary between successive parties that
-- reuse the same physical table number.

CREATE OR REPLACE FUNCTION public.assign_order_table_session()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.session_token IS NOT NULL AND length(trim(NEW.session_token)) > 0 THEN
    SELECT ts.id INTO NEW.table_session_id
    FROM public.table_sessions ts
    WHERE ts.merchant_id = NEW.merchant_id
      AND ts.branch_id = NEW.branch_id
      AND ts.table_number = NEW.table_number
      AND ts.session_token = NEW.session_token
    ORDER BY ts.created_at DESC
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_order_table_session ON public.orders;
CREATE TRIGGER trg_assign_order_table_session
BEFORE INSERT OR UPDATE OF merchant_id, branch_id, table_number, session_token
ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.assign_order_table_session();

UPDATE public.orders o
SET table_session_id = ts.id
FROM public.table_sessions ts
WHERE o.table_session_id IS NULL
  AND o.session_token IS NOT NULL
  AND ts.merchant_id = o.merchant_id
  AND ts.branch_id = o.branch_id
  AND ts.table_number = o.table_number
  AND ts.session_token = o.session_token;

CREATE INDEX IF NOT EXISTS idx_orders_current_table_session
  ON public.orders (merchant_id, branch_id, table_session_id, created_at)
  WHERE is_deleted = false;

NOTIFY pgrst, 'reload schema';
