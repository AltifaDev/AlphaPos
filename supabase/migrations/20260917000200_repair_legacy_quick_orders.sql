-- Repair legacy Quick Orders that were incorrectly persisted as dine_in.
-- The canonical service identity trigger rejects QUICK as a dine-in table.
UPDATE public.orders
SET order_type = 'take_out',
    table_number = 'QUICK',
    table_session_id = NULL,
    updated_at = now()
WHERE upper(COALESCE(table_number, '')) = 'QUICK'
  AND order_type = 'dine_in';
