-- Safe to run against the configured database: all fixture data is rolled back.
-- psql -v ON_ERROR_STOP=1 -f supabase/tests/order_mutation_replay_contract.sql
BEGIN;

SELECT set_config('request.jwt.claims',
    '{"merchant_id":"00000000-0000-0000-0000-000000000011"}', true);

INSERT INTO public.order_mutation_operations
    (merchant_id, operation_id, order_id, request, response)
VALUES (
    '00000000-0000-0000-0000-000000000011',
    'contract-replay-test',
    '00000000-0000-0000-0000-000000000012',
    '{"order":{"id":"00000000-0000-0000-0000-000000000012","merchant_id":"00000000-0000-0000-0000-000000000011"},"items":[],"modifiers":[]}',
    '{"status":"ok","order_id":"00000000-0000-0000-0000-000000000012"}'
);

DO $test$
DECLARE
    result jsonb;
    rejected boolean := false;
BEGIN
    result := public.create_order_atomic_cas(
        '{"id":"00000000-0000-0000-0000-000000000012","merchant_id":"00000000-0000-0000-0000-000000000011","operation_id":"contract-replay-test"}'::jsonb,
        '[]'::jsonb, '[]'::jsonb
    );
    IF result->>'status' IS DISTINCT FROM 'ok' THEN
        RAISE EXCEPTION 'Replay did not return the stored result';
    END IF;

    BEGIN
        PERFORM public.create_order_atomic_cas(
            '{"id":"00000000-0000-0000-0000-000000000012","merchant_id":"00000000-0000-0000-0000-000000000011","operation_id":"contract-replay-test","total":99}'::jsonb,
            '[]'::jsonb, '[]'::jsonb
        );
    EXCEPTION WHEN SQLSTATE '22023' THEN
        rejected := true;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'Changed request reused the operation ID';
    END IF;
END
$test$;

ROLLBACK;
