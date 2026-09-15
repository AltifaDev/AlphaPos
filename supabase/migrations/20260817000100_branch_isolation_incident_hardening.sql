BEGIN;

-- Operational child rows carry branch identity directly. This makes RLS,
-- offline pruning and incident investigation deterministic even when their
-- parent relationship is temporarily unavailable during sync.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'cash_movements','refund_transactions','order_discounts','order_tax_lines',
    'tips','timecards','shift_reports','purchase_order_items','restaurant_walls',
    'printers','print_routing_rules'
  ] LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES public.branches(id) ON DELETE RESTRICT',
      t
    );
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (merchant_id, branch_id)', 'idx_' || t || '_merchant_branch', t);
  END LOOP;
END $$;

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
UPDATE public.purchase_order_items x SET branch_id=o.branch_id
FROM public.purchase_orders o WHERE x.purchase_order_id=o.id AND x.branch_id IS NULL;
UPDATE public.timecards x SET branch_id=e.branch_id
FROM public.employees e WHERE x.employee_id=e.id AND x.branch_id IS NULL;
UPDATE public.shift_reports x SET branch_id=s.branch_id
FROM public.register_sessions s WHERE x.register_session_id=s.id AND x.branch_id IS NULL;

-- Inherit branch identity and reject branch spoofing for direct PostgREST writes.
CREATE OR REPLACE FUNCTION public.enforce_operational_child_branch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_parent_branch uuid;
  v_request_branch uuid := public.get_active_branch_id();
BEGIN
  CASE TG_TABLE_NAME
    WHEN 'cash_movements' THEN SELECT branch_id INTO v_parent_branch FROM public.register_sessions WHERE id=NEW.register_session_id;
    WHEN 'refund_transactions' THEN SELECT branch_id INTO v_parent_branch FROM public.orders WHERE id=NEW.order_id;
    WHEN 'order_discounts' THEN SELECT branch_id INTO v_parent_branch FROM public.orders WHERE id=NEW.order_id;
    WHEN 'order_tax_lines' THEN SELECT branch_id INTO v_parent_branch FROM public.orders WHERE id=NEW.order_id;
    WHEN 'tips' THEN SELECT branch_id INTO v_parent_branch FROM public.orders WHERE id=NEW.order_id;
    WHEN 'purchase_order_items' THEN SELECT branch_id INTO v_parent_branch FROM public.purchase_orders WHERE id=NEW.purchase_order_id;
    WHEN 'timecards' THEN SELECT branch_id INTO v_parent_branch FROM public.employees WHERE id=NEW.employee_id;
    WHEN 'shift_reports' THEN SELECT branch_id INTO v_parent_branch FROM public.register_sessions WHERE id=NEW.register_session_id;
    ELSE v_parent_branch := NEW.branch_id;
  END CASE;

  IF NEW.branch_id IS NULL THEN NEW.branch_id := v_parent_branch; END IF;
  IF v_parent_branch IS NOT NULL AND NEW.branch_id IS DISTINCT FROM v_parent_branch THEN
    RAISE EXCEPTION 'branch_mismatch';
  END IF;
  IF v_request_branch IS NOT NULL AND NEW.branch_id IS DISTINCT FROM v_request_branch THEN
    RAISE EXCEPTION 'branch_mismatch';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'cash_movements','refund_transactions','order_discounts','order_tax_lines',
    'tips','timecards','shift_reports','purchase_order_items'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_enforce_operational_child_branch ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_enforce_operational_child_branch BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_operational_child_branch()',
      t
    );
  END LOOP;
END $$;

-- Paired branch devices are restricted at the database boundary. Merchant-wide
-- owner tokens remain able to use explicit management/reporting workflows.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'cash_movements','refund_transactions','order_discounts','order_tax_lines',
    'tips','timecards','shift_reports','purchase_order_items','restaurant_walls',
    'printers','print_routing_rules','inventory_items','inventory_lots',
    'inventory_transactions','purchase_orders','register_sessions','floor_plan_images',
    'table_layout_presets','dining_areas','merchant_devices'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS branch_scope ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY branch_scope ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (public.get_active_branch_id() IS NULL OR branch_id = public.get_active_branch_id()) WITH CHECK (public.get_active_branch_id() IS NULL OR branch_id = public.get_active_branch_id())',
      t
    );
  END LOOP;
END $$;

-- Never expose physical layouts across every tenant. Customer table JWTs use
-- the existing customer_web_table_read policy; floor-plan media is staff-only.
DROP POLICY IF EXISTS customer_catalog_read ON public.restaurant_tables;
DROP POLICY IF EXISTS customer_catalog_read ON public.restaurant_walls;
DROP POLICY IF EXISTS customer_catalog_read ON public.floor_plan_images;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, TRIGGER, REFERENCES ON public.restaurant_tables FROM anon;
REVOKE ALL ON public.restaurant_walls FROM anon;
REVOKE ALL ON public.floor_plan_images FROM anon;
GRANT SELECT ON public.restaurant_tables TO anon;

-- SECURITY DEFINER functions must enforce both tenant and branch themselves.
CREATE OR REPLACE FUNCTION public.approve_customer_order(p_order_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_merchant_id uuid := public.get_active_merchant_id();
  v_branch_id uuid := public.get_active_branch_id();
BEGIN
  IF v_merchant_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.orders WHERE id=p_order_id AND merchant_id=v_merchant_id
      AND (v_branch_id IS NULL OR branch_id=v_branch_id)
      AND order_source='web' AND is_deleted=false
  ) THEN RAISE EXCEPTION 'customer order not found for active merchant and branch'; END IF;

  IF EXISTS (SELECT 1 FROM public.order_items WHERE order_id=p_order_id AND merchant_id=v_merchant_id AND is_deleted=false)
     AND NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id=p_order_id AND merchant_id=v_merchant_id AND is_deleted=false AND status NOT IN ('served','cancelled')) THEN
    UPDATE public.orders SET status='served',is_staff_confirmed=true,updated_at=now()
      WHERE id=p_order_id AND merchant_id=v_merchant_id AND (v_branch_id IS NULL OR branch_id=v_branch_id);
    RETURN p_order_id;
  END IF;
  UPDATE public.orders SET status='preparing',is_staff_confirmed=true,updated_at=now()
    WHERE id=p_order_id AND merchant_id=v_merchant_id AND (v_branch_id IS NULL OR branch_id=v_branch_id);
  UPDATE public.order_items SET status='cooking',updated_at=now()
    WHERE order_id=p_order_id AND merchant_id=v_merchant_id AND (v_branch_id IS NULL OR branch_id=v_branch_id)
      AND status='pending' AND is_deleted=false;
  RETURN p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_soft_delete_restaurant_tables(p_table_ids uuid[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_merchant_id uuid := public.get_active_merchant_id();
  v_branch_id uuid := public.get_active_branch_id();
  v_deleted_count integer;
BEGIN
  IF v_merchant_id IS NULL OR coalesce(array_length(p_table_ids,1),0)=0 THEN RETURN 0; END IF;
  IF EXISTS (SELECT 1 FROM public.table_sessions s WHERE s.merchant_id=v_merchant_id
      AND (v_branch_id IS NULL OR s.branch_id=v_branch_id) AND s.table_id=ANY(p_table_ids)
      AND s.is_active=1 AND coalesce(s.is_deleted,false)=false) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='cannot delete tables with active sessions';
  END IF;
  UPDATE public.restaurant_tables SET is_deleted=true,updated_at=clock_timestamp()
    WHERE merchant_id=v_merchant_id AND (v_branch_id IS NULL OR branch_id=v_branch_id)
      AND id=ANY(p_table_ids) AND is_deleted=false;
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_sync_health(p_merchant_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_active_merchant uuid := public.get_active_merchant_id();
  v_merchant_id uuid;
  v_pending int:=0; v_failed int:=0; v_processing int:=0; v_oldest timestamptz; v_by_type jsonb:='[]'::jsonb;
BEGIN
  IF v_active_merchant IS NULL OR (p_merchant_id IS NOT NULL AND p_merchant_id IS DISTINCT FROM v_active_merchant) THEN
    RETURN jsonb_build_object('ok',false,'error','merchant_scope_mismatch');
  END IF;
  v_merchant_id := v_active_merchant;
  SELECT count(*) FILTER(WHERE status='pending'),count(*) FILTER(WHERE status='failed'),
         count(*) FILTER(WHERE status='processing'),min(created_at) FILTER(WHERE status IN ('pending','failed','processing'))
    INTO v_pending,v_failed,v_processing,v_oldest FROM public.sync_outbox
    WHERE merchant_id=v_merchant_id AND status IN ('pending','failed','processing');
  SELECT coalesce(jsonb_agg(jsonb_build_object('job_type',job_type,'count',cnt) ORDER BY cnt DESC),'[]'::jsonb)
    INTO v_by_type FROM (SELECT job_type,count(*)::int cnt FROM public.sync_outbox
      WHERE merchant_id=v_merchant_id AND status IN ('pending','failed','processing') GROUP BY job_type) q;
  RETURN jsonb_build_object('ok',true,'merchant_id',v_merchant_id,'pending_count',coalesce(v_pending,0),
    'failed_count',coalesce(v_failed,0),'processing_count',coalesce(v_processing,0),
    'oldest_created_at',v_oldest,'by_job_type',v_by_type,'server_time',now());
END;
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
