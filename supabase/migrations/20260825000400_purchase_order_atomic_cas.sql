BEGIN;

-- Header and lines commit as one transaction. Existing rows require the
-- revision last pulled by the client; missing/stale revisions are conflicts.
CREATE OR REPLACE FUNCTION public.upsert_purchase_order_atomic_cas(
  p_order jsonb,
  p_items jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_id uuid := (p_order->>'id')::uuid;
  v_merchant uuid := (p_order->>'merchant_id')::uuid;
  v_expected bigint := NULLIF(p_order->>'expected_row_version', '')::bigint;
  v_actual bigint;
  v_line jsonb;
  v_line_id uuid;
  v_line_expected bigint;
  v_versions jsonb := '{}'::jsonb;
BEGIN
  IF public.get_active_merchant_id() IS DISTINCT FROM v_merchant THEN
    RAISE EXCEPTION 'merchant_scope_mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT row_version INTO v_actual FROM public.purchase_orders
   WHERE id = v_id AND merchant_id = v_merchant FOR UPDATE;
  IF FOUND AND (v_expected IS NULL OR v_expected <> v_actual) THEN
    RAISE EXCEPTION 'purchase_order_conflict id=% expected=% actual=%', v_id, v_expected, v_actual
      USING ERRCODE = '40001';
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    v_line_id := (v_line->>'id')::uuid;
    v_line_expected := NULLIF(v_line->>'expected_row_version', '')::bigint;
    SELECT row_version INTO v_actual FROM public.purchase_order_items
     WHERE id = v_line_id AND merchant_id = v_merchant FOR UPDATE;
    IF FOUND AND (v_line_expected IS NULL OR v_line_expected <> v_actual) THEN
      RAISE EXCEPTION 'purchase_order_item_conflict id=% expected=% actual=%', v_line_id, v_line_expected, v_actual
        USING ERRCODE = '40001';
    END IF;
  END LOOP;

  INSERT INTO public.purchase_orders (
    id, merchant_id, supplier_id, branch_id, po_number, status, order_date,
    delivery_date, notes, is_synced, is_deleted, updated_at, document_type,
    invoice_number, tax_invoice_number, supplier_name_raw, supplier_tax_id,
    supplier_branch_code, customer_reference, invoice_date, currency_code,
    subtotal, tax_amount, grand_total, extraction_confidence,
    validation_warnings, source_document_hash
  ) VALUES (
    v_id, v_merchant, NULLIF(p_order->>'supplier_id','')::uuid,
    NULLIF(p_order->>'branch_id','')::uuid, p_order->>'po_number',
    COALESCE(p_order->>'status','draft'), COALESCE((p_order->>'order_date')::timestamptz, now()),
    NULLIF(p_order->>'delivery_date','')::timestamptz, p_order->>'notes', TRUE,
    COALESCE((p_order->>'is_deleted')::boolean,FALSE), COALESCE((p_order->>'updated_at')::timestamptz,now()),
    p_order->>'document_type', p_order->>'invoice_number', p_order->>'tax_invoice_number',
    p_order->>'supplier_name_raw', p_order->>'supplier_tax_id', p_order->>'supplier_branch_code',
    p_order->>'customer_reference', NULLIF(p_order->>'invoice_date','')::date,
    COALESCE(p_order->>'currency_code','THB'), NULLIF(p_order->>'subtotal','')::numeric,
    NULLIF(p_order->>'tax_amount','')::numeric, NULLIF(p_order->>'grand_total','')::numeric,
    NULLIF(p_order->>'extraction_confidence','')::numeric,
    COALESCE(p_order->'validation_warnings','[]'::jsonb), p_order->>'source_document_hash'
  ) ON CONFLICT (id) DO UPDATE SET
    supplier_id=EXCLUDED.supplier_id, branch_id=EXCLUDED.branch_id, po_number=EXCLUDED.po_number,
    status=EXCLUDED.status, order_date=EXCLUDED.order_date, delivery_date=EXCLUDED.delivery_date,
    notes=EXCLUDED.notes, is_synced=TRUE, is_deleted=EXCLUDED.is_deleted, updated_at=EXCLUDED.updated_at,
    document_type=EXCLUDED.document_type, invoice_number=EXCLUDED.invoice_number,
    tax_invoice_number=EXCLUDED.tax_invoice_number, supplier_name_raw=EXCLUDED.supplier_name_raw,
    supplier_tax_id=EXCLUDED.supplier_tax_id, supplier_branch_code=EXCLUDED.supplier_branch_code,
    customer_reference=EXCLUDED.customer_reference, invoice_date=EXCLUDED.invoice_date,
    currency_code=EXCLUDED.currency_code, subtotal=EXCLUDED.subtotal, tax_amount=EXCLUDED.tax_amount,
    grand_total=EXCLUDED.grand_total, extraction_confidence=EXCLUDED.extraction_confidence,
    validation_warnings=EXCLUDED.validation_warnings, source_document_hash=EXCLUDED.source_document_hash;

  FOR v_line IN SELECT value FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    v_line_id := (v_line->>'id')::uuid;
    INSERT INTO public.purchase_order_items (
      id, merchant_id, purchase_order_id, inventory_item_id, quantity_ordered,
      quantity_received, unit_cost, is_synced, is_deleted, updated_at, line_number,
      source_item_name, seller_item_id, barcode, source_unit, unit_code,
      price_base_quantity, line_net_amount, vat_rate, vat_code, tax_amount,
      line_total, line_confidence, expiry_date, lot_number
    ) VALUES (
      v_line_id, v_merchant, v_id, NULLIF(v_line->>'inventory_item_id','')::uuid,
      COALESCE((v_line->>'quantity_ordered')::numeric,0), COALESCE((v_line->>'quantity_received')::numeric,0),
      COALESCE((v_line->>'unit_cost')::numeric,0), TRUE, COALESCE((v_line->>'is_deleted')::boolean,FALSE),
      COALESCE((v_line->>'updated_at')::timestamptz,now()), v_line->>'line_number',
      v_line->>'source_item_name', v_line->>'seller_item_id', v_line->>'barcode',
      v_line->>'source_unit', v_line->>'unit_code', COALESCE((v_line->>'price_base_quantity')::numeric,1),
      NULLIF(v_line->>'line_net_amount','')::numeric, NULLIF(v_line->>'vat_rate','')::numeric,
      v_line->>'vat_code', NULLIF(v_line->>'tax_amount','')::numeric,
      NULLIF(v_line->>'line_total','')::numeric, NULLIF(v_line->>'line_confidence','')::numeric,
      NULLIF(v_line->>'expiry_date','')::date, v_line->>'lot_number'
    ) ON CONFLICT (id) DO UPDATE SET
      purchase_order_id=EXCLUDED.purchase_order_id, inventory_item_id=EXCLUDED.inventory_item_id,
      quantity_ordered=EXCLUDED.quantity_ordered, quantity_received=EXCLUDED.quantity_received,
      unit_cost=EXCLUDED.unit_cost, is_synced=TRUE, is_deleted=EXCLUDED.is_deleted,
      updated_at=EXCLUDED.updated_at, line_number=EXCLUDED.line_number,
      source_item_name=EXCLUDED.source_item_name, seller_item_id=EXCLUDED.seller_item_id,
      barcode=EXCLUDED.barcode, source_unit=EXCLUDED.source_unit, unit_code=EXCLUDED.unit_code,
      price_base_quantity=EXCLUDED.price_base_quantity, line_net_amount=EXCLUDED.line_net_amount,
      vat_rate=EXCLUDED.vat_rate, vat_code=EXCLUDED.vat_code, tax_amount=EXCLUDED.tax_amount,
      line_total=EXCLUDED.line_total, line_confidence=EXCLUDED.line_confidence,
      expiry_date=EXCLUDED.expiry_date, lot_number=EXCLUDED.lot_number;
    SELECT row_version INTO v_actual FROM public.purchase_order_items WHERE id=v_line_id;
    v_versions := v_versions || jsonb_build_object(lower(v_line_id::text),v_actual);
  END LOOP;

  SELECT row_version INTO v_actual FROM public.purchase_orders WHERE id=v_id;
  RETURN jsonb_build_object('purchase_order_id',v_id,'purchase_order_row_version',v_actual,'item_row_versions',v_versions);
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_purchase_order_atomic_cas(jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_purchase_order_atomic_cas(jsonb,jsonb) TO anon, authenticated, service_role;

COMMIT;
