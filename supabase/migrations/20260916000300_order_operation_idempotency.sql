-- Record an order mutation and its result in the same transaction. A lost HTTP
-- response can then be replayed without applying the mutation a second time.
BEGIN;

CREATE TABLE public.order_mutation_operations (
    merchant_id uuid NOT NULL,
    operation_id text NOT NULL CHECK (length(operation_id) BETWEEN 1 AND 160),
    order_id uuid NOT NULL,
    request jsonb NOT NULL,
    response jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (merchant_id, operation_id)
);

CREATE INDEX order_mutation_operations_order_idx
    ON public.order_mutation_operations (merchant_id, order_id, created_at DESC);

ALTER TABLE public.order_mutation_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_mutation_operations FROM PUBLIC, anon, authenticated;

-- Keep the already-deployed CAS implementation as an internal function. It
-- still owns revision checks, stable row-lock ordering and line_type updates.
ALTER FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb)
    RENAME TO create_order_atomic_cas_inner;
REVOKE ALL ON FUNCTION public.create_order_atomic_cas_inner(jsonb,jsonb,jsonb)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.create_order_atomic_cas(
    p_order jsonb,
    p_items jsonb,
    p_modifiers jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_merchant_id uuid := (p_order->>'merchant_id')::uuid;
    v_order_id uuid := (p_order->>'id')::uuid;
    v_operation_id text := NULLIF(btrim(p_order->>'operation_id'), '');
    v_session_token text := NULLIF(p_order->>'session_token', '');
    v_items jsonb;
    v_modifiers jsonb;
    v_request jsonb;
    v_previous_request jsonb;
    v_previous_response jsonb;
    v_previous_order_id uuid;
    v_response jsonb;
    v_inserted integer;
BEGIN
    -- Validate the caller before looking up a previously stored response.
    IF public.get_active_merchant_id() IS DISTINCT FROM v_merchant_id THEN
        IF v_session_token IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.table_sessions ts
            WHERE ts.merchant_id = v_merchant_id
              AND ts.session_token = v_session_token
              AND ts.is_active = 1
              AND COALESCE(ts.is_deleted, false) = false
        ) THEN
            RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Older clients remain compatible with the CAS contract. Updated clients
    -- must provide an operation ID for replay protection.
    IF v_operation_id IS NULL THEN
        RETURN public.create_order_atomic_cas_inner(p_order, p_items, p_modifiers);
    END IF;
    IF length(v_operation_id) > 160 THEN
        RAISE EXCEPTION 'operation_id_too_long' USING ERRCODE = '22023';
    END IF;

    -- Transport-generated timestamps and modifier row IDs can change on a
    -- retry. Compare the actual business request, retaining every line and
    -- modifier value and their multiplicities.
    SELECT COALESCE(jsonb_agg(value - 'created_at' ORDER BY value->>'id'), '[]'::jsonb)
      INTO v_items
      FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) AS item(value);
    SELECT COALESCE(jsonb_agg(value - 'id' ORDER BY (value - 'id')::text), '[]'::jsonb)
      INTO v_modifiers
      FROM jsonb_array_elements(COALESCE(p_modifiers, '[]'::jsonb)) AS modifier(value);
    v_request := jsonb_build_object(
        'order', p_order - ARRAY['operation_id', 'created_at', 'updated_at'],
        'items', v_items,
        'modifiers', v_modifiers
    );

    PERFORM set_config('lock_timeout', '2000ms', true);
    INSERT INTO public.order_mutation_operations
        (merchant_id, operation_id, order_id, request)
    VALUES (v_merchant_id, v_operation_id, v_order_id, v_request)
    ON CONFLICT (merchant_id, operation_id) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    IF v_inserted = 0 THEN
        SELECT operation.request, operation.response, operation.order_id
          INTO v_previous_request, v_previous_response, v_previous_order_id
          FROM public.order_mutation_operations AS operation
         WHERE operation.merchant_id = v_merchant_id
           AND operation.operation_id = v_operation_id;
        IF v_previous_request IS DISTINCT FROM v_request
           OR v_previous_order_id IS DISTINCT FROM v_order_id THEN
            RAISE EXCEPTION 'operation_id_reused_with_different_request'
                USING ERRCODE = '22023';
        END IF;
        IF v_previous_response IS NULL THEN
            RAISE EXCEPTION 'operation_result_unavailable' USING ERRCODE = '55P03';
        END IF;
        RETURN v_previous_response;
    END IF;

    -- A failure in the existing CAS function rolls back the ledger insertion.
    v_response := public.create_order_atomic_cas_inner(p_order, p_items, p_modifiers);
    UPDATE public.order_mutation_operations
       SET response = v_response
     WHERE merchant_id = v_merchant_id AND operation_id = v_operation_id;
    RETURN v_response;
END;
$$;

REVOKE ALL ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_atomic_cas(jsonb,jsonb,jsonb)
    TO anon, authenticated, service_role;

COMMIT;
