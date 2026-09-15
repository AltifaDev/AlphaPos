-- Canonical cross-client order contract.
-- Web, iPad and iPhone use table_session_id as the sole current-bill identity.

ALTER TABLE public.table_sessions
  ADD COLUMN IF NOT EXISTS bundle_revision BIGINT NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION public.enforce_order_session_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_session public.table_sessions;
BEGIN
  IF NEW.table_session_id IS NOT NULL THEN
    SELECT * INTO v_session FROM public.table_sessions WHERE id = NEW.table_session_id;
  ELSIF NULLIF(NEW.session_token, '') IS NOT NULL THEN
    SELECT * INTO v_session FROM public.table_sessions WHERE session_token = NEW.session_token;
  END IF;

  IF v_session.id IS NULL THEN
    IF NEW.order_source = 'web' AND COALESCE(NEW.order_type, 'dine_in') = 'dine_in' THEN
      RAISE EXCEPTION 'web_dine_in_order_requires_active_table_session'
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF v_session.is_active <> 1 OR v_session.ended_at IS NOT NULL THEN
    RAISE EXCEPTION 'order_table_session_is_closed' USING ERRCODE = '23514';
  END IF;
  IF NEW.merchant_id IS DISTINCT FROM v_session.merchant_id
     OR NEW.branch_id IS DISTINCT FROM v_session.branch_id
     OR NEW.table_number IS DISTINCT FROM v_session.table_number THEN
    RAISE EXCEPTION 'order_table_session_scope_mismatch' USING ERRCODE = '23514';
  END IF;

  NEW.table_session_id := v_session.id;
  NEW.session_token := v_session.session_token;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_enforce_session_scope ON public.orders;
CREATE TRIGGER trg_orders_enforce_session_scope
  BEFORE INSERT OR UPDATE OF table_session_id, session_token, merchant_id, branch_id, table_number
  ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.enforce_order_session_scope();

-- Repair legacy orders before clients switch to the canonical UUID contract.
UPDATE public.orders o
SET table_session_id = s.id
FROM public.table_sessions s
WHERE o.table_session_id IS NULL
  AND NULLIF(o.session_token, '') IS NOT NULL
  AND o.session_token = s.session_token
  AND o.merchant_id = s.merchant_id
  AND o.branch_id = s.branch_id
  AND o.table_number = s.table_number;

CREATE OR REPLACE FUNCTION public.enforce_order_item_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_order public.orders;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = NEW.order_id;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'order_item_parent_missing' USING ERRCODE = '23503';
  END IF;
  IF NEW.merchant_id IS DISTINCT FROM v_order.merchant_id
     OR NEW.branch_id IS DISTINCT FROM v_order.branch_id THEN
    RAISE EXCEPTION 'order_item_scope_mismatch' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_items_enforce_scope ON public.order_items;
CREATE TRIGGER trg_order_items_enforce_scope
  BEFORE INSERT OR UPDATE OF order_id, merchant_id, branch_id
  ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public.enforce_order_item_scope();

CREATE OR REPLACE FUNCTION public.bump_order_bundle_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id UUID;
  v_merchant_id UUID;
  v_branch_id UUID;
  v_revision BIGINT;
  v_order_id UUID;
BEGIN
  IF TG_TABLE_NAME = 'orders' THEN
    v_session_id := COALESCE(NEW.table_session_id, OLD.table_session_id);
    v_order_id := COALESCE(NEW.id, OLD.id);
  ELSIF TG_TABLE_NAME = 'order_items' THEN
    v_order_id := COALESCE(NEW.order_id, OLD.order_id);
    SELECT table_session_id INTO v_session_id FROM public.orders WHERE id = v_order_id;
  ELSIF TG_TABLE_NAME = 'order_item_modifiers' THEN
    SELECT oi.order_id, o.table_session_id INTO v_order_id, v_session_id
    FROM public.order_items oi JOIN public.orders o ON o.id = oi.order_id
    WHERE oi.id = COALESCE(NEW.order_item_id, OLD.order_item_id);
  ELSIF TG_TABLE_NAME = 'payments' THEN
    v_order_id := COALESCE(NEW.order_id, OLD.order_id);
    SELECT table_session_id INTO v_session_id FROM public.orders WHERE id = v_order_id;
  END IF;

  IF v_session_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  UPDATE public.table_sessions
  SET bundle_revision = bundle_revision + 1
  WHERE id = v_session_id
  RETURNING merchant_id, branch_id, bundle_revision
  INTO v_merchant_id, v_branch_id, v_revision;

  INSERT INTO public.sync_outbox(merchant_id, idempotency_key, job_type, payload)
  VALUES (
    v_merchant_id,
    'order-bundle:' || v_session_id::text || ':' || txid_current()::text,
    'order_bundle.changed',
    jsonb_build_object(
      'contract_version', 1, 'table_session_id', v_session_id,
      'order_id', v_order_id, 'branch_id', v_branch_id,
      'revision', v_revision, 'occurred_at', now()
    )
  )
  ON CONFLICT (merchant_id, idempotency_key) DO UPDATE
  SET payload = EXCLUDED.payload, status = 'pending', updated_at = now();

  RETURN COALESCE(NEW, OLD);
END;
$$;

DO $$
DECLARE v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['orders','order_items','order_item_modifiers','payments'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%I_order_bundle_revision ON public.%I', v_table, v_table);
    EXECUTE format(
      'CREATE TRIGGER trg_%I_order_bundle_revision AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.bump_order_bundle_revision()',
      v_table, v_table
    );
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.get_table_order_bundle(
  p_table_session_id UUID,
  p_branch_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id UUID := public.get_active_merchant_id();
  v_claim_branch UUID := public.get_active_branch_id();
  v_session public.table_sessions;
  v_orders JSONB;
BEGIN
  IF v_merchant_id IS NULL OR p_table_session_id IS NULL THEN
    RAISE EXCEPTION 'order_bundle_auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM public.table_sessions s
  WHERE s.id = p_table_session_id
    AND s.merchant_id = v_merchant_id
    AND s.branch_id = COALESCE(v_claim_branch, p_branch_id, s.branch_id);
  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'order_bundle_session_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(order_json ORDER BY created_at), '[]'::jsonb)
  INTO v_orders
  FROM (
    SELECT o.created_at,
      to_jsonb(o) || jsonb_build_object(
        'order_items', COALESCE((
          SELECT jsonb_agg(
            to_jsonb(oi) || jsonb_build_object(
              'order_item_modifiers', COALESCE((
                SELECT jsonb_agg(to_jsonb(oim) || jsonb_build_object(
                  'modifiers', CASE WHEN m.id IS NULL THEN NULL ELSE jsonb_build_object('name', m.name) END
                ) ORDER BY oim.id)
                FROM public.order_item_modifiers oim
                LEFT JOIN public.modifiers m ON m.id = oim.modifier_id
                WHERE oim.order_item_id = oi.id
              ), '[]'::jsonb)
            ) ORDER BY oi.created_at, oi.id
          ) FROM public.order_items oi
          WHERE oi.order_id = o.id AND NOT COALESCE(oi.is_deleted, false)
        ), '[]'::jsonb),
        'payments', COALESCE((
          SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at, p.id)
          FROM public.payments p WHERE p.order_id = o.id
        ), '[]'::jsonb)
      ) AS order_json
    FROM public.orders o
    WHERE o.table_session_id = v_session.id
      AND o.merchant_id = v_session.merchant_id
      AND o.branch_id = v_session.branch_id
      AND NOT COALESCE(o.is_deleted, false)
  ) rows;

  RETURN jsonb_build_object(
    'contract_version', 1,
    'server_time', now(),
    'revision', v_session.bundle_revision,
    'table_session', to_jsonb(v_session),
    'orders', v_orders
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_table_order_bundle(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_table_order_bundle(UUID, UUID) TO anon, authenticated, customer_web, service_role;

CREATE INDEX IF NOT EXISTS idx_orders_active_session_bundle
  ON public.orders(table_session_id, created_at, id)
  WHERE NOT COALESCE(is_deleted, false);
CREATE INDEX IF NOT EXISTS idx_order_items_bundle
  ON public.order_items(order_id, created_at, id)
  WHERE NOT COALESCE(is_deleted, false);

NOTIFY pgrst, 'reload schema';
