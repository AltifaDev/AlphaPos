-- The POS previously patched accounting columns after the order RPC. That
-- second request advanced row_version again, leaving the device with a stale
-- revision and allowing a partial commit if the patch failed. Keep all order
-- fields and the final revision in the same idempotent RPC transaction.
BEGIN;

ALTER FUNCTION public.create_order_atomic_cas_inner(jsonb,jsonb,jsonb)
    RENAME TO create_order_atomic_cas_core;
REVOKE ALL ON FUNCTION public.create_order_atomic_cas_core(jsonb,jsonb,jsonb)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.create_order_atomic_cas_inner(
    p_order jsonb,
    p_items jsonb,
    p_modifiers jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_result jsonb;
    v_order_id uuid;
    v_merchant_id uuid := (p_order->>'merchant_id')::uuid;
    v_final_version bigint;
BEGIN
    v_result := public.create_order_atomic_cas_core(p_order, p_items, p_modifiers);
    v_order_id := (v_result->>'order_id')::uuid;

    -- Older Staff clients omit these optional fields. Do not touch their
    -- order header merely to populate defaults or advance its revision.
    IF p_order ?| ARRAY[
        'support_program_name', 'support_government_rate',
        'support_citizen_amount', 'support_government_amount',
        'support_settlement_status', 'business_date', 'register_session_id'
    ] THEN
        UPDATE public.orders AS o
           SET support_program_name = CASE WHEN p_order ? 'support_program_name'
                   THEN NULLIF(p_order->>'support_program_name', '')
                   ELSE o.support_program_name END,
               support_government_rate = CASE WHEN p_order ? 'support_government_rate'
                   THEN COALESCE((p_order->>'support_government_rate')::numeric, 0)
                   ELSE o.support_government_rate END,
               support_citizen_amount = CASE WHEN p_order ? 'support_citizen_amount'
                   THEN COALESCE((p_order->>'support_citizen_amount')::numeric, 0)
                   ELSE o.support_citizen_amount END,
               support_government_amount = CASE WHEN p_order ? 'support_government_amount'
                   THEN COALESCE((p_order->>'support_government_amount')::numeric, 0)
                   ELSE o.support_government_amount END,
               support_settlement_status = CASE WHEN p_order ? 'support_settlement_status'
                   THEN COALESCE(NULLIF(p_order->>'support_settlement_status', ''), 'not_applicable')
                   ELSE o.support_settlement_status END,
               business_date = CASE WHEN p_order ? 'business_date'
                   THEN NULLIF(p_order->>'business_date', '')::date
                   ELSE o.business_date END,
               register_session_id = CASE WHEN p_order ? 'register_session_id'
                   THEN NULLIF(p_order->>'register_session_id', '')::uuid
                   ELSE o.register_session_id END
         WHERE o.id = v_order_id AND o.merchant_id = v_merchant_id
         RETURNING o.row_version INTO v_final_version;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'order_not_found_after_atomic_write' USING ERRCODE = 'P0002';
        END IF;
        v_result := jsonb_set(v_result, '{order_row_version}', to_jsonb(v_final_version));
    END IF;
    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_order_atomic_cas_inner(jsonb,jsonb,jsonb)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
