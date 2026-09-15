BEGIN;

-- Revoke the legacy credential that was previously bundled in AlphaPosStaff.
-- Staff now uses one-time pairing + opaque refresh credentials only.
UPDATE public.merchant_devices
SET revoked_at = COALESCE(revoked_at, now()), is_trusted = false, updated_at = now()
WHERE credential_hash = 'ddbbed716773b6ccd7e3fd1414d519cbc5b69943e625b16c107fadf908c65198';
UPDATE public.merchants
SET device_secret_hash = NULL
WHERE device_secret_hash = 'ddbbed716773b6ccd7e3fd1414d519cbc5b69943e625b16c107fadf908c65198';

-- Branch identity carried by paired-device JWTs. POS merchant tokens without a
-- branch remain merchant-wide for management workflows.
CREATE OR REPLACE FUNCTION public.get_active_branch_id()
RETURNS UUID
LANGUAGE sql STABLE
AS $$
    SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'branch_id', '')::uuid
$$;

ALTER TABLE public.restaurant_tables ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.table_sessions ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.service_requests ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.employee_breaks ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.chat_channels ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_orders_merchant_idempotency
    ON public.orders (merchant_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_merchant_idempotency
    ON public.payments (merchant_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_merchant_branch_active ON public.orders (merchant_id, branch_id, status) WHERE COALESCE(is_deleted, false) = false;
CREATE INDEX IF NOT EXISTS idx_tables_merchant_branch ON public.restaurant_tables (merchant_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_sessions_merchant_branch_active ON public.table_sessions (merchant_id, branch_id, is_active);

-- Safe legacy backfill only where the merchant has exactly one branch. Multi-
-- branch merchants must explicitly assign old operational rows before rollout.
WITH only_branch AS (
  SELECT merchant_id, (array_agg(id))[1] AS branch_id FROM public.branches GROUP BY merchant_id HAVING count(*) = 1
)
UPDATE public.orders x SET branch_id=b.branch_id FROM only_branch b WHERE x.merchant_id=b.merchant_id AND x.branch_id IS NULL;
WITH only_branch AS (
  SELECT merchant_id, (array_agg(id))[1] AS branch_id FROM public.branches GROUP BY merchant_id HAVING count(*) = 1
)
UPDATE public.restaurant_tables x SET branch_id=b.branch_id FROM only_branch b WHERE x.merchant_id=b.merchant_id AND x.branch_id IS NULL;
WITH only_branch AS (
  SELECT merchant_id, (array_agg(id))[1] AS branch_id FROM public.branches GROUP BY merchant_id HAVING count(*) = 1
)
UPDATE public.table_sessions x SET branch_id=b.branch_id FROM only_branch b WHERE x.merchant_id=b.merchant_id AND x.branch_id IS NULL;
UPDATE public.order_items i SET branch_id=o.branch_id FROM public.orders o WHERE i.order_id=o.id AND i.branch_id IS NULL;
UPDATE public.payments p SET branch_id=o.branch_id FROM public.orders o WHERE p.order_id=o.id AND p.branch_id IS NULL;

-- Approved production mapping (2026-08-11): all legacy data for the primary
-- merchant belongs to the first Main Branch, which is also the paired Staff
-- device branch. Keep this explicit; never guess for other multi-branch tenants.
UPDATE public.orders SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.order_items SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.payments SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.restaurant_tables SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.table_sessions SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.service_requests SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.employees SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.employee_shifts SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.employee_breaks SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.chat_channels SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.chat_messages SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.merchant_devices SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331', updated_at=now()
WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;

-- Explicitly approved legacy mapping (2026-08-11): all unscoped data for the
-- AlphaPos test merchant belongs to its first Main Branch.
UPDATE public.orders SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.restaurant_tables SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.table_sessions SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.service_requests SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.order_items SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.payments SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.employees SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.employee_shifts SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.employee_breaks SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.chat_channels SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.chat_messages SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331'
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;
UPDATE public.merchant_devices SET branch_id='5037e6ed-03da-4d4c-9777-68ad37899331', updated_at=now()
 WHERE merchant_id='163350b0-056d-4d5e-b5d4-24e7aac5ab6d' AND branch_id IS NULL;

CREATE OR REPLACE FUNCTION public.assign_request_branch()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_branch UUID := public.get_active_branch_id();
BEGIN
    IF NEW.branch_id IS NULL THEN NEW.branch_id := v_branch; END IF;
    IF v_branch IS NOT NULL AND NEW.branch_id IS DISTINCT FROM v_branch THEN
        RAISE EXCEPTION 'branch_mismatch';
    END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['orders','restaurant_tables','table_sessions','service_requests','employee_breaks','chat_channels','chat_messages']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_assign_request_branch ON public.%I', t);
    EXECUTE format('CREATE TRIGGER trg_assign_request_branch BEFORE INSERT OR UPDATE OF branch_id ON public.%I FOR EACH ROW EXECUTE FUNCTION public.assign_request_branch()', t);
  END LOOP;
END $$;

-- Existing merchant policies remain in place. These restrictive policies add
-- branch isolation only when the JWT carries a paired-device branch claim.
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['orders','order_items','payments','restaurant_tables','table_sessions','service_requests','employees','employee_shifts','employee_breaks','chat_channels','chat_messages']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS branch_scope ON public.%I', t);
    EXECUTE format('CREATE POLICY branch_scope ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (public.get_active_branch_id() IS NULL OR branch_id = public.get_active_branch_id()) WITH CHECK (public.get_active_branch_id() IS NULL OR branch_id = public.get_active_branch_id())', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS branch_scope ON public.order_item_modifiers;
ALTER TABLE public.order_item_modifiers ENABLE ROW LEVEL SECURITY;
CREATE POLICY branch_scope ON public.order_item_modifiers AS RESTRICTIVE FOR ALL TO anon, authenticated
USING (
  public.get_active_branch_id() IS NULL OR EXISTS (
    SELECT 1 FROM public.order_items i
    WHERE i.id = order_item_modifiers.order_item_id AND i.branch_id = public.get_active_branch_id()
  )
)
WITH CHECK (
  public.get_active_branch_id() IS NULL OR EXISTS (
    SELECT 1 FROM public.order_items i
    WHERE i.id = order_item_modifiers.order_item_id AND i.branch_id = public.get_active_branch_id()
  )
);

CREATE OR REPLACE FUNCTION public.inherit_order_branch()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.branch_id IS NULL THEN NEW.branch_id := (SELECT branch_id FROM public.orders WHERE id = NEW.order_id); END IF;
    IF public.get_active_branch_id() IS NOT NULL AND NEW.branch_id IS DISTINCT FROM public.get_active_branch_id() THEN
        RAISE EXCEPTION 'branch_mismatch';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_order_items_inherit_branch ON public.order_items;
CREATE TRIGGER trg_order_items_inherit_branch BEFORE INSERT OR UPDATE OF order_id, branch_id ON public.order_items FOR EACH ROW EXECUTE FUNCTION public.inherit_order_branch();
DROP TRIGGER IF EXISTS trg_payments_inherit_branch ON public.payments;
CREATE TRIGGER trg_payments_inherit_branch BEFORE INSERT OR UPDATE OF order_id, branch_id ON public.payments FOR EACH ROW EXECUTE FUNCTION public.inherit_order_branch();

CREATE TABLE IF NOT EXISTS public.checkout_operations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('processing','completed','failed')),
    request JSONB NOT NULL DEFAULT '{}'::jsonb,
    response JSONB,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, idempotency_key)
);
ALTER TABLE public.checkout_operations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS checkout_operations_scope ON public.checkout_operations;
CREATE POLICY checkout_operations_scope ON public.checkout_operations FOR ALL TO anon, authenticated
USING (merchant_id = public.get_active_merchant_id() AND (public.get_active_branch_id() IS NULL OR branch_id = public.get_active_branch_id()))
WITH CHECK (merchant_id = public.get_active_merchant_id() AND (public.get_active_branch_id() IS NULL OR branch_id = public.get_active_branch_id()));

-- Shared checkout state transition for Staff and POS. One database transaction,
-- deterministic payment IDs, and a durable result make retries safe.
CREATE OR REPLACE FUNCTION public.complete_checkout_atomic(
    p_order_id UUID,
    p_idempotency_key TEXT,
    p_payments JSONB,
    p_table_number TEXT DEFAULT 'QUICK',
    p_breakdown JSONB DEFAULT '{}'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
    v_existing public.checkout_operations%ROWTYPE;
    v_payment JSONB;
    v_total NUMERIC := 0;
    v_response JSONB;
    v_branch UUID := public.get_active_branch_id();
BEGIN
    IF NULLIF(trim(p_idempotency_key), '') IS NULL OR jsonb_array_length(COALESCE(p_payments, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'invalid_checkout_request';
    END IF;
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND OR v_order.merchant_id IS DISTINCT FROM public.get_active_merchant_id() THEN RAISE EXCEPTION 'order_not_found'; END IF;
    IF v_branch IS NOT NULL AND v_order.branch_id IS DISTINCT FROM v_branch THEN RAISE EXCEPTION 'branch_mismatch'; END IF;

    SELECT * INTO v_existing FROM public.checkout_operations
      WHERE merchant_id = v_order.merchant_id AND idempotency_key = p_idempotency_key;
    IF FOUND AND v_existing.state = 'completed' THEN RETURN v_existing.response; END IF;

    INSERT INTO public.checkout_operations(merchant_id, branch_id, order_id, idempotency_key, state, request)
    VALUES(v_order.merchant_id, v_order.branch_id, p_order_id, p_idempotency_key, 'processing',
           jsonb_build_object('payments', p_payments, 'breakdown', p_breakdown))
    ON CONFLICT (merchant_id, idempotency_key) DO UPDATE SET state='processing', updated_at=now();

    FOR v_payment IN SELECT value FROM jsonb_array_elements(p_payments) LOOP
        IF COALESCE((v_payment->>'amount')::numeric, 0) <= 0 THEN RAISE EXCEPTION 'invalid_payment_amount'; END IF;
        INSERT INTO public.payments(id, merchant_id, branch_id, order_id, amount, payment_method, status, created_at, idempotency_key)
        VALUES((v_payment->>'id')::uuid, v_order.merchant_id, v_order.branch_id, p_order_id,
               (v_payment->>'amount')::numeric, v_payment->>'payment_method', 'completed', now(),
               p_idempotency_key || ':' || (v_payment->>'id'))
        ON CONFLICT (id) DO NOTHING;
        v_total := v_total + (v_payment->>'amount')::numeric;
    END LOOP;
    IF abs(v_total - COALESCE((p_breakdown->>'grand_total')::numeric, v_order.total)) > 0.05 THEN
        RAISE EXCEPTION 'payment_total_mismatch';
    END IF;

    UPDATE public.orders SET status='completed', subtotal=COALESCE((p_breakdown->>'subtotal')::numeric, NULLIF(subtotal,0), total),
      tax=COALESCE((p_breakdown->>'tax')::numeric,tax), service_charge=COALESCE((p_breakdown->>'service_charge')::numeric,service_charge),
      discount=COALESCE((p_breakdown->>'discount')::numeric,discount), total=v_total, updated_at=now() WHERE id=p_order_id;
    UPDATE public.order_items SET status='served' WHERE order_id=p_order_id AND status <> 'cancelled';
    IF upper(COALESCE(p_table_number,'QUICK')) <> 'QUICK' THEN
      UPDATE public.table_sessions SET is_active=0, ended_at=now() WHERE merchant_id=v_order.merchant_id AND branch_id IS NOT DISTINCT FROM v_order.branch_id AND table_number=p_table_number AND is_active=1;
      UPDATE public.restaurant_tables SET status='cleaning', updated_at=now() WHERE merchant_id=v_order.merchant_id AND branch_id IS NOT DISTINCT FROM v_order.branch_id AND table_number=p_table_number;
    END IF;
    v_response := jsonb_build_object('status','completed','order_id',p_order_id,'amount',v_total,'idempotency_key',p_idempotency_key);
    UPDATE public.checkout_operations SET state='completed', response=v_response, updated_at=now() WHERE merchant_id=v_order.merchant_id AND idempotency_key=p_idempotency_key;
    RETURN v_response;
END;
$$;
GRANT EXECUTE ON FUNCTION public.complete_checkout_atomic(UUID,TEXT,JSONB,TEXT,JSONB) TO anon, authenticated;

COMMIT;
