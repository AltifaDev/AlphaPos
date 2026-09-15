BEGIN;

-- Permanent branch identity invariant. Parent-derived values are repaired first;
-- remaining NULLs are safe to infer only for merchants that own one live branch.
UPDATE public.payments p SET branch_id=o.branch_id
FROM public.orders o WHERE p.order_id=o.id AND p.branch_id IS NULL;
UPDATE public.order_items x SET branch_id=o.branch_id
FROM public.orders o WHERE x.order_id=o.id AND x.branch_id IS NULL;
UPDATE public.cash_movements x SET branch_id=s.branch_id
FROM public.register_sessions s WHERE x.register_session_id=s.id AND x.branch_id IS NULL;
UPDATE public.refund_transactions x SET branch_id=o.branch_id
FROM public.orders o WHERE x.order_id=o.id AND x.branch_id IS NULL;
UPDATE public.order_discounts x SET branch_id=o.branch_id
FROM public.orders o WHERE x.order_id=o.id AND x.branch_id IS NULL;
UPDATE public.order_tax_lines x SET branch_id=o.branch_id
FROM public.orders o WHERE x.order_id=o.id AND x.branch_id IS NULL;
UPDATE public.tips x SET branch_id=o.branch_id
FROM public.orders o WHERE x.order_id=o.id AND x.branch_id IS NULL;
UPDATE public.shift_reports x SET branch_id=s.branch_id
FROM public.register_sessions s WHERE x.register_session_id=s.id AND x.branch_id IS NULL;
UPDATE public.purchase_order_items x SET branch_id=o.branch_id
FROM public.purchase_orders o WHERE x.purchase_order_id=o.id AND x.branch_id IS NULL;

-- Recover inventory provenance from the order item that caused the movement.
UPDATE public.inventory_transactions x SET branch_id=o.branch_id
FROM public.order_items oi
JOIN public.orders o ON o.id=oi.order_id
WHERE x.reference_id=oi.id AND x.branch_id IS NULL;

-- An item is safe to recover only when all branch-known movements agree.
UPDATE public.inventory_items i SET branch_id=x.branch_id
FROM (
  SELECT item_id, min(branch_id::text)::uuid AS branch_id
  FROM public.inventory_transactions
  WHERE branch_id IS NOT NULL
  GROUP BY item_id
  HAVING count(DISTINCT branch_id)=1
) x
WHERE i.id=x.item_id AND i.branch_id IS NULL;

-- Opening/adjustment movements without an order inherit the now-proven item branch.
UPDATE public.inventory_transactions x SET branch_id=i.branch_id
FROM public.inventory_items i
WHERE x.item_id=i.id AND x.branch_id IS NULL AND i.branch_id IS NOT NULL;

CREATE TEMP TABLE _single_branch_merchants ON COMMIT DROP AS
SELECT merchant_id, min(id::text)::uuid AS branch_id
FROM public.branches
GROUP BY merchant_id
HAVING count(*)=1;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'orders','order_items','payments','inventory_items','inventory_transactions',
    'purchase_orders','purchase_order_items','register_sessions','cash_movements',
    'refund_transactions','order_discounts','order_tax_lines','tips','shift_reports',
    'expenses','restaurant_tables','table_sessions','dining_areas','floor_plan_images',
    'table_layout_presets','restaurant_walls','printers','print_routing_rules'
  ] LOOP
    IF to_regclass('public.' || t) IS NOT NULL
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='branch_id') THEN
      EXECUTE format(
        'UPDATE public.%I x SET branch_id=b.branch_id FROM _single_branch_merchants b WHERE x.merchant_id=b.merchant_id AND x.branch_id IS NULL', t
      );
    END IF;
  END LOOP;
END $$;

-- Never guess ownership in a multi-branch merchant. Abort with a precise table
-- name so operators can repair those rows explicitly before retrying migration.
DO $$
DECLARE t text; missing_count bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'orders','order_items','payments','inventory_items','inventory_transactions',
    'purchase_orders','purchase_order_items','register_sessions','cash_movements',
    'refund_transactions','order_discounts','order_tax_lines','tips','shift_reports',
    'expenses','restaurant_tables','table_sessions','dining_areas','floor_plan_images',
    'table_layout_presets','restaurant_walls','printers','print_routing_rules'
  ] LOOP
    IF to_regclass('public.' || t) IS NOT NULL
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='branch_id') THEN
      EXECUTE format('SELECT count(*) FROM public.%I WHERE branch_id IS NULL', t) INTO missing_count;
      IF missing_count > 0 THEN
        RAISE EXCEPTION 'branch_integrity_unresolved: table=% null_rows=%; assign these rows explicitly before retrying', t, missing_count;
      END IF;
    END IF;
  END LOOP;
END $$;

-- Replace permissive SET NULL foreign keys, then make the invariant physical.
DO $$
DECLARE t text; c record;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'orders','order_items','payments','inventory_items','inventory_transactions',
    'purchase_orders','purchase_order_items','register_sessions','cash_movements',
    'refund_transactions','order_discounts','order_tax_lines','tips','shift_reports',
    'expenses','restaurant_tables','table_sessions','dining_areas','floor_plan_images',
    'table_layout_presets','restaurant_walls','printers','print_routing_rules'
  ] LOOP
    IF to_regclass('public.' || t) IS NULL
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='branch_id') THEN
      CONTINUE;
    END IF;
    FOR c IN
      SELECT conname FROM pg_constraint
      WHERE conrelid=('public.' || t)::regclass AND contype='f'
        AND pg_get_constraintdef(oid) LIKE 'FOREIGN KEY (branch_id)%'
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', t, c.conname);
    END LOOP;
    EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE RESTRICT', t, t || '_branch_id_fkey');
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN branch_id SET NOT NULL', t);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (merchant_id, branch_id)', 'idx_' || t || '_merchant_branch_required', t);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
