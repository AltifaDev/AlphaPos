-- Fix checkout failures caused by two overloaded enqueue_sync_outbox RPCs.
--
-- The legacy 4-argument function and the newer 6-argument function both had
-- defaultable arguments. Calls made with four arguments therefore matched
-- both functions and PostgreSQL raised 42725 (ambiguous_function). Payment
-- inserts run inside complete_checkout_atomic, so the whole checkout rolled
-- back and the Staff app reported a misleading connection error.

BEGIN;

-- Keep the branch-aware/priority-aware implementation introduced by
-- 20260916000700. Remove only the obsolete legacy overload.
DROP FUNCTION IF EXISTS public.enqueue_sync_outbox(TEXT, TEXT, JSONB, UUID);

-- Make the intended signature explicit for future callers and deployments.
REVOKE ALL ON FUNCTION public.enqueue_sync_outbox(TEXT, TEXT, JSONB, UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_sync_outbox(TEXT, TEXT, JSONB, UUID, UUID, INTEGER)
    TO anon, authenticated, service_role;

COMMIT;
