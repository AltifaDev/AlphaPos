BEGIN;

-- Conflict-aware facade for POS/KDS writes. Row locks are retained until the
-- delegated atomic upsert completes, closing the check-then-write race.
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
  IF public.get_active_merchant_id() IS DISTINCT FROM v_merchant_id
     AND NULLIF(p_order->>'session_token', '') IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;

  -- Match the canonical-ID resolution performed by create_order_atomic so a
  -- retry carrying an alternate UUID cannot bypass the revision check.
  SELECT id INTO v_order_id
  FROM public.orders
  WHERE merchant_id = v_merchant_id
    AND order_number = NULLIF(trim(p_order->>'order_number'), '')
  LIMIT 1;
  v_order_id := COALESCE(v_order_id, (p_order->>'id')::uuid);

  SELECT row_version INTO v_actual
  FROM public.orders
  WHERE id = v_order_id AND merchant_id = v_merchant_id
  FOR UPDATE;

  IF FOUND AND (v_expected IS NULL OR v_expected <> v_actual) THEN
    RAISE EXCEPTION 'order_conflict id=% expected=% actual=%', v_order_id, v_expected, v_actual
      USING ERRCODE = '40001';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    v_item_id := (v_item->>'id')::uuid;
    v_item_expected := NULLIF(v_item->>'expected_row_version', '')::bigint;
    SELECT row_version INTO v_item_actual
    FROM public.order_items
    WHERE id = v_item_id AND merchant_id = v_merchant_id
    FOR UPDATE;
    IF FOUND AND (v_item_expected IS NULL OR v_item_expected <> v_item_actual) THEN
      RAISE EXCEPTION 'order_item_conflict id=% expected=% actual=%', v_item_id, v_item_expected, v_item_actual
        USING ERRCODE = '40001';
    END IF;
  END LOOP;

  v_result := public.create_order_atomic(p_order, p_items, p_modifiers);

  SELECT row_version INTO v_actual FROM public.orders WHERE id = (v_result->>'order_id')::uuid;
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

REVOKE ALL ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb) TO anon, authenticated, service_role;

COMMIT;
