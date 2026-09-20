-- Prevent a burst of concurrent order syncs from exhausting PostgREST's
-- connection pool while waiting on the same order row.
--
-- The client already sends stable order/item UUIDs and the canonical RPC is
-- idempotent, so a short, bounded retry is safe.  NOWAIT makes contention a
-- fast transient failure instead of leaving a Postgres connection blocked.

BEGIN;

-- Direct callers of the canonical RPC (older clients, web ordering, or
-- operational scripts) must also fail fast while a conflicting write is in
-- progress.  SET LOCAL is scoped to this RPC transaction only.
CREATE OR REPLACE FUNCTION public.create_order_atomic(
    p_order     JSONB,
    p_items     JSONB,
    p_modifiers JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_order_id         UUID   := (p_order->>'id')::UUID;
    v_merchant_id      UUID   := (p_order->>'merchant_id')::UUID;
    v_active_merchant  UUID   := public.get_active_merchant_id();
    v_session_token    TEXT   := NULLIF(p_order->>'session_token', '');
    v_order_number     TEXT   := NULLIF(TRIM(p_order->>'order_number'), '');
    v_branch_id        UUID   := COALESCE(NULLIF(p_order->>'branch_id', '')::UUID, public.get_active_branch_id());
    v_existing_id      UUID;
    v_item             JSONB;
    v_modifier         JSONB;
    v_item_count       INT    := 0;
BEGIN
    PERFORM set_config('lock_timeout', '2000ms', true);
    PERFORM set_config('statement_timeout', '12000ms', true);

    IF v_active_merchant IS DISTINCT FROM v_merchant_id THEN
        IF v_session_token IS NULL THEN
            RAISE EXCEPTION 'auth_required: merchant JWT or session_token required';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.table_sessions ts
            WHERE ts.merchant_id   = v_merchant_id
              AND ts.session_token = v_session_token
              AND ts.is_active     = 1
              AND COALESCE(ts.is_deleted, false) = false
        ) THEN
            RAISE EXCEPTION 'session_invalid: no active table session for token';
        END IF;
    END IF;

    IF jsonb_array_length(COALESCE(p_items, '[]'::JSONB)) = 0 THEN
        RAISE EXCEPTION 'items_required: order must contain at least one item';
    END IF;

    IF v_order_number IS NOT NULL THEN
        SELECT id INTO v_existing_id
        FROM public.orders
        WHERE merchant_id = v_merchant_id AND order_number = v_order_number
        LIMIT 1;
        IF v_existing_id IS NOT NULL THEN
            v_order_id := v_existing_id;
        END IF;
    END IF;

    INSERT INTO public.orders (
        id, order_number, table_number, total, status,
        order_type, cashier_name, queue_number, receipt_number,
        created_at, updated_at, merchant_id, branch_id, session_token,
        ready_at, delivery_brand, delivery_gp, delivery_ad_fee,
        delivery_ad_fee_is_pct, delivery_other_fee,
        platform_order_number, order_source, is_staff_confirmed,
        is_deleted
    ) VALUES (
        v_order_id,
        COALESCE(v_order_number, 'ORD-' || substring(v_order_id::text from 1 for 8)),
        COALESCE(NULLIF(p_order->>'table_number', ''), 'QUICK'),
        COALESCE((p_order->>'total')::NUMERIC, 0),
        COALESCE(p_order->>'status', 'preparing'),
        COALESCE(p_order->>'order_type', 'dine_in'),
        COALESCE(p_order->>'cashier_name', 'Staff'),
        NULLIF(p_order->>'queue_number', ''),
        NULLIF(p_order->>'receipt_number', ''),
        COALESCE((p_order->>'created_at')::TIMESTAMPTZ, now()),
        COALESCE((p_order->>'updated_at')::TIMESTAMPTZ, now()),
        v_merchant_id,
        v_branch_id,
        v_session_token,
        (p_order->>'ready_at')::TIMESTAMPTZ,
        NULLIF(p_order->>'delivery_brand', ''),
        COALESCE((p_order->>'delivery_gp')::NUMERIC, 0),
        COALESCE((p_order->>'delivery_ad_fee')::NUMERIC, 0),
        COALESCE((p_order->>'delivery_ad_fee_is_pct')::BOOLEAN, false),
        COALESCE((p_order->>'delivery_other_fee')::NUMERIC, 0),
        NULLIF(TRIM(COALESCE(p_order->>'platform_order_number', '')), ''),
        COALESCE(NULLIF(p_order->>'order_source', ''), 'pos'),
        COALESCE((p_order->>'is_staff_confirmed')::BOOLEAN, true),
        false
    )
    ON CONFLICT (id) DO UPDATE SET
        status                 = EXCLUDED.status,
        total                  = EXCLUDED.total,
        order_type             = EXCLUDED.order_type,
        cashier_name           = EXCLUDED.cashier_name,
        branch_id              = COALESCE(EXCLUDED.branch_id, public.orders.branch_id),
        queue_number           = COALESCE(EXCLUDED.queue_number, public.orders.queue_number),
        receipt_number         = COALESCE(EXCLUDED.receipt_number, public.orders.receipt_number),
        updated_at             = EXCLUDED.updated_at,
        delivery_brand         = EXCLUDED.delivery_brand,
        delivery_gp            = EXCLUDED.delivery_gp,
        delivery_ad_fee        = EXCLUDED.delivery_ad_fee,
        delivery_ad_fee_is_pct = EXCLUDED.delivery_ad_fee_is_pct,
        delivery_other_fee     = EXCLUDED.delivery_other_fee,
        platform_order_number  = COALESCE(EXCLUDED.platform_order_number, public.orders.platform_order_number),
        order_source           = COALESCE(EXCLUDED.order_source, public.orders.order_source),
        is_staff_confirmed     = COALESCE(EXCLUDED.is_staff_confirmed, public.orders.is_staff_confirmed);

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
        INSERT INTO public.order_items (
            id, order_id, item_name, quantity, price, status,
            item_id, merchant_id, branch_id, notes, served_by, created_at
        ) VALUES (
            (v_item->>'id')::UUID,
            v_order_id,
            v_item->>'item_name',
            (v_item->>'quantity')::INTEGER,
            (v_item->>'price')::NUMERIC,
            COALESCE(v_item->>'status', 'cooking'),
            NULLIF(v_item->>'item_id', ''),
            v_merchant_id,
            COALESCE(NULLIF(v_item->>'branch_id', '')::UUID, v_branch_id),
            NULLIF(v_item->>'notes', ''),
            NULLIF(v_item->>'served_by', ''),
            COALESCE((v_item->>'created_at')::TIMESTAMPTZ, now())
        )
        ON CONFLICT (id) DO UPDATE SET
            quantity   = EXCLUDED.quantity,
            price      = EXCLUDED.price,
            status     = EXCLUDED.status,
            item_name  = EXCLUDED.item_name,
            notes      = EXCLUDED.notes,
            served_by  = EXCLUDED.served_by;
        v_item_count := v_item_count + 1;
    END LOOP;

    FOR v_modifier IN SELECT value FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::JSONB)) LOOP
        INSERT INTO public.order_item_modifiers (
            id, order_item_id, modifier_id, price, merchant_id
        ) VALUES (
            (v_modifier->>'id')::UUID,
            (v_modifier->>'order_item_id')::UUID,
            NULLIF(v_modifier->>'modifier_id', '')::UUID,
            COALESCE((v_modifier->>'price')::NUMERIC, 0),
            v_merchant_id
        )
        ON CONFLICT (id) DO NOTHING;
    END LOOP;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'items_count', v_item_count,
        'status', 'ok'
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_order_atomic_cas(
    p_order jsonb,
    p_items jsonb,
    p_modifiers jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_order_id uuid := (p_order->>'id')::uuid;
  v_merchant_id uuid := (p_order->>'merchant_id')::uuid;
  v_expected bigint := NULLIF(p_order->>'expected_row_version', '')::bigint;
  v_actual bigint;
  v_item jsonb;
  v_item_id uuid;
  v_item_expected bigint;
  v_item_actual bigint;
  v_result jsonb;
  v_versions jsonb := '{}'::jsonb;
BEGIN
  PERFORM set_config('lock_timeout', '2000ms', true);
  PERFORM set_config('statement_timeout', '12000ms', true);

  IF public.get_active_merchant_id() IS DISTINCT FROM v_merchant_id
     AND NULLIF(p_order->>'session_token', '') IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_order_id
  FROM public.orders
  WHERE merchant_id = v_merchant_id
    AND order_number = NULLIF(trim(p_order->>'order_number'), '')
  LIMIT 1;
  v_order_id := COALESCE(v_order_id, (p_order->>'id')::uuid);

  -- Do not hold a PostgREST connection in a lock queue.  The client retries
  -- this transient 55P03 error with bounded backoff.
  BEGIN
    SELECT row_version INTO v_actual
    FROM public.orders
    WHERE id = v_order_id AND merchant_id = v_merchant_id
    FOR UPDATE NOWAIT;
  EXCEPTION WHEN lock_not_available THEN
    RAISE EXCEPTION 'order_busy id=%', v_order_id USING ERRCODE = '55P03';
  END;

  IF FOUND AND (v_expected IS NULL OR v_expected <> v_actual) THEN
    RAISE EXCEPTION 'order_conflict id=% expected=% actual=%', v_order_id, v_expected, v_actual
      USING ERRCODE = '40001';
  END IF;

  -- Lock item rows in a stable UUID order to avoid deadlocks when two clients
  -- submit the same order with differently ordered item arrays.
  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
    ORDER BY (value->>'id')::uuid
  LOOP
    v_item_id := (v_item->>'id')::uuid;
    v_item_expected := NULLIF(v_item->>'expected_row_version', '')::bigint;
    BEGIN
      SELECT row_version INTO v_item_actual
      FROM public.order_items
      WHERE id = v_item_id AND merchant_id = v_merchant_id
      FOR UPDATE NOWAIT;
    EXCEPTION WHEN lock_not_available THEN
      RAISE EXCEPTION 'order_item_busy id=%', v_item_id USING ERRCODE = '55P03';
    END;
    IF FOUND AND (v_item_expected IS NULL OR v_item_expected <> v_item_actual) THEN
      RAISE EXCEPTION 'order_item_conflict id=% expected=% actual=%', v_item_id, v_item_expected, v_item_actual
        USING ERRCODE = '40001';
    END IF;
  END LOOP;

  v_result := public.create_order_atomic(p_order, p_items, p_modifiers);

  -- Preserve the immutable kitchen/sales classification introduced by the
  -- later order-item migration. Legacy callers that omit line_type continue
  -- to use the menu-role trigger inside create_order_atomic.
  UPDATE public.order_items oi
  SET line_type = NULLIF(src.value->>'line_type', '')
  FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) AS src(value)
  WHERE oi.id = (src.value->>'id')::uuid
    AND oi.merchant_id = v_merchant_id
    AND NULLIF(src.value->>'line_type', '')
        IN ('main', 'addon', 'bundle_component', 'promotion_reward')
    AND oi.line_type IS DISTINCT FROM NULLIF(src.value->>'line_type', '');

  SELECT row_version INTO v_actual
  FROM public.orders
  WHERE id = (v_result->>'order_id')::uuid;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    v_item_id := (v_item->>'id')::uuid;
    SELECT row_version INTO v_item_actual FROM public.order_items WHERE id = v_item_id;
    v_versions := v_versions || jsonb_build_object(lower(v_item_id::text), v_item_actual);
  END LOOP;

  RETURN v_result || jsonb_build_object(
    'order_row_version', v_actual,
    'item_row_versions', v_versions
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_order_atomic(jsonb,jsonb,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_atomic(jsonb,jsonb,jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb) TO anon, authenticated, service_role;

COMMIT;
