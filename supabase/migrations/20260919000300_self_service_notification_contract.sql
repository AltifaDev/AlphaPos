-- Self-service web orders are already accepted by the customer-order RPC.
-- Keep the notification actionable (send to kitchen), not an approval request.

CREATE OR REPLACE FUNCTION private.trg_fn_push_web_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.order_source = 'web' AND NEW.status IN ('pending', 'preparing') THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   'web_order',
      'merchant_id',  NEW.merchant_id::text,
      'order_id',     NEW.id::text,
      'order_number', NEW.order_number::text,
      'table_number', NEW.table_number,
      'message',      'New web order received — send to kitchen'
    ));
  END IF;
  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION private.trg_fn_push_web_order() TO service_role;
