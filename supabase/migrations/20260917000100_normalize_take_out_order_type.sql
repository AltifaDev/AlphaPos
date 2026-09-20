-- Canonical order type is take_out across POS and AlphaPosStaff.
-- Keep this idempotent for databases that already contain only canonical rows.
UPDATE public.orders
SET order_type = 'take_out', updated_at = COALESCE(updated_at, now())
WHERE order_type = 'takeaway';

COMMENT ON COLUMN public.orders.order_type IS
  'dine_in, take_out, delivery, walk_in; take_out is the canonical takeaway value';
