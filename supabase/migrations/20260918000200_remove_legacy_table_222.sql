-- Remove the deleted legacy table 222 for the affected production tenant.
-- Preserve any historical sale by converting its service identity to Quick.

BEGIN;

UPDATE public.orders
SET order_type = 'take_out', table_number = 'QUICK', table_session_id = NULL, updated_at = now()
WHERE merchant_id = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'::uuid
  AND branch_id = '5037e6ed-03da-4d4c-9777-68ad37899331'::uuid
  AND btrim(table_number) = '222';

DELETE FROM public.table_sessions
WHERE merchant_id = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'::uuid
  AND branch_id = '5037e6ed-03da-4d4c-9777-68ad37899331'::uuid
  AND btrim(table_number) = '222';

DELETE FROM public.restaurant_tables
WHERE merchant_id = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'::uuid
  AND branch_id = '5037e6ed-03da-4d4c-9777-68ad37899331'::uuid
  AND btrim(table_number) = '222';

COMMIT;
