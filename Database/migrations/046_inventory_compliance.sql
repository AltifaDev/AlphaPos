-- AlphaPos inventory compliance foundation
-- Recall/quarantine, receiving inspection, temperature evidence, blind counts,
-- per-item packaging conversion and atomic/idempotent branch transfer.

CREATE TABLE IF NOT EXISTS public.inventory_lot_controls (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    branch_id uuid NOT NULL REFERENCES public.branches(id),
    inventory_item_id uuid NOT NULL REFERENCES public.inventory_items(id),
    lot_id uuid NOT NULL REFERENCES public.inventory_lots(id),
    disposition text NOT NULL CHECK (disposition IN ('available','quarantined','released','rejected','recalled','destroyed')),
    reason_code text NOT NULL,
    notes text,
    decided_by_employee_id uuid REFERENCES public.employees(id),
    approved_by_employee_id uuid REFERENCES public.employees(id),
    decided_at timestamptz NOT NULL DEFAULT now(),
    released_at timestamptz,
    is_deleted boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, lot_id)
);

CREATE TABLE IF NOT EXISTS public.inventory_recalls (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    recall_number text NOT NULL,
    title text NOT NULL,
    reason_code text NOT NULL,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','contained','closed')),
    severity text NOT NULL DEFAULT 'medium' CHECK (severity IN ('low','medium','high','critical')),
    initiated_by_employee_id uuid REFERENCES public.employees(id),
    approved_by_employee_id uuid REFERENCES public.employees(id),
    initiated_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    corrective_action text,
    effectiveness_verified_at timestamptz,
    is_deleted boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, recall_number)
);

CREATE TABLE IF NOT EXISTS public.inventory_recall_lots (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    recall_id uuid NOT NULL REFERENCES public.inventory_recalls(id),
    lot_id uuid NOT NULL REFERENCES public.inventory_lots(id),
    inventory_item_id uuid NOT NULL REFERENCES public.inventory_items(id),
    branch_id uuid NOT NULL REFERENCES public.branches(id),
    affected_quantity numeric(18,4) NOT NULL CHECK (affected_quantity >= 0),
    recovered_quantity numeric(18,4) NOT NULL DEFAULT 0 CHECK (recovered_quantity >= 0),
    destroyed_quantity numeric(18,4) NOT NULL DEFAULT 0 CHECK (destroyed_quantity >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, recall_id, lot_id)
);

CREATE TABLE IF NOT EXISTS public.incoming_inspections (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    branch_id uuid NOT NULL REFERENCES public.branches(id),
    purchase_order_id uuid REFERENCES public.purchase_orders(id),
    purchase_order_item_id uuid REFERENCES public.purchase_order_items(id),
    inventory_item_id uuid NOT NULL REFERENCES public.inventory_items(id),
    lot_id uuid REFERENCES public.inventory_lots(id),
    supplier_id uuid REFERENCES public.suppliers(id),
    inspected_by_employee_id uuid REFERENCES public.employees(id),
    inspected_at timestamptz NOT NULL DEFAULT now(),
    received_quantity numeric(18,4) NOT NULL CHECK (received_quantity >= 0),
    rejected_quantity numeric(18,4) NOT NULL DEFAULT 0 CHECK (rejected_quantity >= 0),
    temperature_celsius numeric(7,2),
    minimum_temperature numeric(7,2),
    maximum_temperature numeric(7,2),
    packaging_passed boolean NOT NULL DEFAULT true,
    expiry_passed boolean NOT NULL DEFAULT true,
    certificate_reference text,
    decision text NOT NULL CHECK (decision IN ('accepted','quarantined','rejected')),
    reason_code text,
    notes text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.temperature_logs (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    branch_id uuid NOT NULL REFERENCES public.branches(id),
    storage_location text NOT NULL,
    inventory_item_id uuid REFERENCES public.inventory_items(id),
    lot_id uuid REFERENCES public.inventory_lots(id),
    temperature_celsius numeric(7,2) NOT NULL,
    minimum_allowed numeric(7,2) NOT NULL,
    maximum_allowed numeric(7,2) NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by_employee_id uuid REFERENCES public.employees(id),
    source text NOT NULL DEFAULT 'manual',
    corrective_action text,
    verified_by_employee_id uuid REFERENCES public.employees(id),
    verified_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (minimum_allowed <= maximum_allowed)
);

CREATE TABLE IF NOT EXISTS public.inventory_count_sessions (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    branch_id uuid NOT NULL REFERENCES public.branches(id),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','recount_required','approved','posted','rejected')),
    blind_count boolean NOT NULL DEFAULT true,
    counted_by_employee_id uuid REFERENCES public.employees(id),
    submitted_at timestamptz,
    approved_by_employee_id uuid REFERENCES public.employees(id),
    approved_at timestamptz,
    recount_threshold_percent numeric(7,3) NOT NULL DEFAULT 5 CHECK (recount_threshold_percent >= 0),
    notes text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (approved_by_employee_id IS NULL OR approved_by_employee_id IS DISTINCT FROM counted_by_employee_id)
);

CREATE TABLE IF NOT EXISTS public.item_unit_conversions (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    inventory_item_id uuid NOT NULL REFERENCES public.inventory_items(id),
    supplier_id uuid REFERENCES public.suppliers(id),
    from_unit text NOT NULL,
    to_unit text NOT NULL,
    multiplier numeric(18,6) NOT NULL CHECK (multiplier > 0),
    effective_from timestamptz NOT NULL DEFAULT now(),
    effective_to timestamptz,
    is_deleted boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_transfer_requests (
    id uuid PRIMARY KEY,
    merchant_id uuid NOT NULL,
    source_item_id uuid NOT NULL REFERENCES public.inventory_items(id),
    target_item_id uuid NOT NULL REFERENCES public.inventory_items(id),
    quantity numeric(18,4) NOT NULL CHECK (quantity > 0),
    requested_by_employee_id uuid REFERENCES public.employees(id),
    approved_by_employee_id uuid REFERENCES public.employees(id),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lot_controls_disposition ON public.inventory_lot_controls(merchant_id, branch_id, disposition);
CREATE INDEX IF NOT EXISTS idx_recall_lots_lot ON public.inventory_recall_lots(merchant_id, lot_id);
CREATE INDEX IF NOT EXISTS idx_temperature_excursion ON public.temperature_logs(merchant_id, branch_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_inspections_supplier ON public.incoming_inspections(merchant_id, supplier_id, inspected_at DESC);

ALTER TABLE public.inventory_lot_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_recalls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_recall_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incoming_inspections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.temperature_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_count_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_unit_conversions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transfer_requests ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['inventory_lot_controls','inventory_recalls','inventory_recall_lots',
    'incoming_inspections','temperature_logs','inventory_count_sessions','item_unit_conversions','inventory_transfer_requests']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS merchant_isolation ON public.%I', t);
    EXECUTE format('CREATE POLICY merchant_isolation ON public.%I FOR ALL TO anon USING (merchant_id = public.get_active_merchant_id()) WITH CHECK (merchant_id = public.get_active_merchant_id())', t);
  END LOOP;
END $$;

-- Outbound movement may never consume stock from a quarantined/recalled/rejected
-- lot. Quantity remains physically visible but is excluded from availability.
CREATE OR REPLACE FUNCTION public.inventory_quarantine_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE available_quantity numeric;
BEGIN
  IF COALESCE(NEW.transaction_type, NEW.type) IN ('sell','waste','return_to_supplier','transfer_out') THEN
    SELECT COALESCE(SUM(l.remaining_quantity), 0) INTO available_quantity
    FROM public.inventory_lots l
    LEFT JOIN public.inventory_lot_controls c
      ON c.merchant_id = l.merchant_id AND c.lot_id = l.id AND NOT c.is_deleted
    WHERE l.merchant_id = NEW.merchant_id AND l.inventory_item_id = NEW.item_id
      AND NOT COALESCE(l.is_deleted, false) AND l.remaining_quantity > 0
      AND COALESCE(c.disposition, 'available') NOT IN ('quarantined','rejected','recalled','destroyed');
    IF available_quantity < abs(NEW.quantity) THEN
      RAISE EXCEPTION 'insufficient_released_stock';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS zz_inventory_quarantine_guard ON public.inventory_transactions;
CREATE TRIGGER zz_inventory_quarantine_guard
BEFORE INSERT ON public.inventory_transactions
FOR EACH ROW EXECUTE FUNCTION public.inventory_quarantine_guard();

CREATE OR REPLACE FUNCTION public.activate_inventory_recall(
  p_recall_id uuid, p_merchant_id uuid, p_approved_by uuid
) RETURNS integer LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE affected integer;
BEGIN
  UPDATE public.inventory_recalls SET status = 'active', approved_by_employee_id = p_approved_by,
      updated_at = now()
   WHERE id = p_recall_id AND merchant_id = p_merchant_id AND status = 'draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'recall_not_draft_or_not_found'; END IF;

  INSERT INTO public.inventory_lot_controls(id, merchant_id, branch_id, inventory_item_id,
      lot_id, disposition, reason_code, approved_by_employee_id, decided_at, updated_at)
  SELECT gen_random_uuid(), rl.merchant_id, rl.branch_id, rl.inventory_item_id,
      rl.lot_id, 'recalled', 'active_recall', p_approved_by, now(), now()
  FROM public.inventory_recall_lots rl WHERE rl.recall_id = p_recall_id
  ON CONFLICT (merchant_id, lot_id) DO UPDATE SET disposition = 'recalled',
      reason_code = 'active_recall', approved_by_employee_id = EXCLUDED.approved_by_employee_id,
      updated_at = now(), is_deleted = false;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END $$;

CREATE OR REPLACE FUNCTION public.transfer_inventory_compliant(
    p_transfer_id uuid, p_merchant_id uuid, p_source_item_id uuid,
    p_target_item_id uuid, p_quantity numeric, p_requested_by uuid,
    p_approved_by uuid, p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE source_row public.inventory_items%ROWTYPE;
DECLARE target_row public.inventory_items%ROWTYPE;
DECLARE request_inserted boolean := false;
DECLARE existing_request public.inventory_transfer_requests%ROWTYPE;
BEGIN
  IF p_quantity <= 0 THEN RAISE EXCEPTION 'quantity_must_be_positive'; END IF;

  SELECT * INTO source_row FROM public.inventory_items
   WHERE id = p_source_item_id AND merchant_id = p_merchant_id AND NOT is_deleted FOR UPDATE;
  SELECT * INTO target_row FROM public.inventory_items
   WHERE id = p_target_item_id AND merchant_id = p_merchant_id AND NOT is_deleted FOR UPDATE;
  IF source_row.id IS NULL OR target_row.id IS NULL THEN RAISE EXCEPTION 'inventory_item_not_found'; END IF;
  IF source_row.branch_id = target_row.branch_id THEN RAISE EXCEPTION 'different_branches_required'; END IF;
  IF source_row.current_quantity < p_quantity THEN RAISE EXCEPTION 'insufficient_stock'; END IF;
  IF (SELECT COALESCE(SUM(l.remaining_quantity), 0)
      FROM public.inventory_lots l
      LEFT JOIN public.inventory_lot_controls c
        ON c.merchant_id = l.merchant_id AND c.lot_id = l.id AND NOT c.is_deleted
      WHERE l.merchant_id = p_merchant_id AND l.inventory_item_id = p_source_item_id
        AND NOT COALESCE(l.is_deleted, false)
        AND COALESCE(c.disposition, 'available') NOT IN ('quarantined','rejected','recalled','destroyed')) < p_quantity
  THEN RAISE EXCEPTION 'insufficient_released_stock'; END IF;

  INSERT INTO public.inventory_transfer_requests(id, merchant_id, source_item_id, target_item_id,
      quantity, requested_by_employee_id, approved_by_employee_id, notes)
  VALUES (p_transfer_id, p_merchant_id, p_source_item_id, p_target_item_id,
      p_quantity, p_requested_by, p_approved_by, p_notes)
  ON CONFLICT (id) DO NOTHING
  RETURNING true INTO request_inserted;

  -- The insert is the idempotency gate. It is atomic under concurrent retries,
  -- unlike a separate EXISTS check followed by INSERT.
  IF NOT COALESCE(request_inserted, false) THEN
    SELECT * INTO existing_request
      FROM public.inventory_transfer_requests WHERE id = p_transfer_id;
    IF existing_request.merchant_id IS DISTINCT FROM p_merchant_id
       OR existing_request.source_item_id IS DISTINCT FROM p_source_item_id
       OR existing_request.target_item_id IS DISTINCT FROM p_target_item_id
       OR existing_request.quantity IS DISTINCT FROM p_quantity
    THEN
      RAISE EXCEPTION 'transfer_id_reused_with_different_payload';
    END IF;
    RETURN jsonb_build_object('transfer_id', p_transfer_id, 'duplicate', true);
  END IF;

  -- inventory_transactions is the ledger source of truth; its existing trigger
  -- updates inventory_items.current_quantity. Updating both here and through
  -- the ledger would double-apply every transfer.
  INSERT INTO public.inventory_transactions(id, merchant_id, item_id, item_name, branch_id,
      transaction_type, quantity, reference_id, notes, reason_code, created_at, updated_at)
  VALUES
    (gen_random_uuid(), p_merchant_id, source_row.id, source_row.name, source_row.branch_id,
     'transfer_out', -p_quantity, p_transfer_id, p_notes, 'transfer', now(), now()),
    (gen_random_uuid(), p_merchant_id, target_row.id, target_row.name, target_row.branch_id,
     'transfer_in', p_quantity, p_transfer_id, p_notes, 'transfer', now(), now());

  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'duplicate', false,
    'source_quantity', source_row.current_quantity - p_quantity,
    'target_quantity', target_row.current_quantity + p_quantity);
END $$;

CREATE OR REPLACE VIEW public.inventory_recall_impact AS
SELECT r.merchant_id, r.id AS recall_id, r.recall_number, r.status,
       rl.lot_id, rl.inventory_item_id, rl.branch_id, rl.affected_quantity,
       rl.recovered_quantity, rl.destroyed_quantity,
       COALESCE(SUM(a.quantity), 0) AS quantity_sold_from_lot,
       COUNT(DISTINCT a.reference_id) AS affected_sale_references
FROM public.inventory_recalls r
JOIN public.inventory_recall_lots rl ON rl.recall_id = r.id
LEFT JOIN public.inventory_lot_allocations a ON a.lot_id = rl.lot_id
GROUP BY r.merchant_id, r.id, r.recall_number, r.status, rl.lot_id,
         rl.inventory_item_id, rl.branch_id, rl.affected_quantity,
         rl.recovered_quantity, rl.destroyed_quantity;

CREATE OR REPLACE VIEW public.supplier_inventory_scorecard AS
SELECT i.merchant_id, i.supplier_id,
       COUNT(*) AS inspection_count,
       AVG(CASE WHEN i.decision = 'accepted' THEN 100.0 ELSE 0.0 END) AS acceptance_rate_percent,
       AVG(CASE WHEN i.packaging_passed THEN 100.0 ELSE 0.0 END) AS packaging_pass_percent,
       AVG(CASE WHEN i.temperature_celsius BETWEEN i.minimum_temperature AND i.maximum_temperature THEN 100.0
                WHEN i.temperature_celsius IS NULL THEN NULL ELSE 0.0 END) AS temperature_compliance_percent,
       SUM(i.rejected_quantity) AS rejected_quantity
FROM public.incoming_inspections i
WHERE i.supplier_id IS NOT NULL
GROUP BY i.merchant_id, i.supplier_id;
