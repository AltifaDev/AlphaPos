BEGIN;

-- Cross-branch movement is a merchant-owner management workflow. A paired
-- branch JWT must never be able to debit another branch through this definer.
CREATE OR REPLACE FUNCTION public.transfer_inventory_atomic(
  p_transfer_id uuid, p_merchant_id uuid, p_source_item_id uuid,
  p_target_item_id uuid, p_quantity numeric, p_notes text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_source public.inventory_items%ROWTYPE;
  v_target public.inventory_items%ROWTYPE;
BEGIN
  PERFORM public.assert_inventory_tenant(p_merchant_id);
  IF public.get_active_branch_id() IS NOT NULL THEN
    RAISE EXCEPTION 'cross_branch_transfer_requires_merchant_manager';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_source_item_id=p_target_item_id THEN
    RAISE EXCEPTION 'Invalid transfer';
  END IF;
  IF (SELECT count(*)=2 FROM public.inventory_transactions
      WHERE merchant_id=p_merchant_id AND reference_id=p_transfer_id
        AND ((item_id=p_source_item_id AND transaction_type='transfer_out')
          OR (item_id=p_target_item_id AND transaction_type='transfer_in'))) THEN
    RETURN p_transfer_id;
  END IF;
  PERFORM id FROM public.inventory_items
    WHERE id IN (p_source_item_id,p_target_item_id) AND merchant_id=p_merchant_id
      AND coalesce(is_deleted,false)=false ORDER BY id FOR UPDATE;
  SELECT * INTO v_source FROM public.inventory_items WHERE id=p_source_item_id AND merchant_id=p_merchant_id;
  SELECT * INTO v_target FROM public.inventory_items WHERE id=p_target_item_id AND merchant_id=p_merchant_id;
  IF v_source.id IS NULL OR v_target.id IS NULL THEN RAISE EXCEPTION 'Transfer item not found'; END IF;
  IF v_source.branch_id IS NULL OR v_target.branch_id IS NULL OR v_source.branch_id=v_target.branch_id THEN
    RAISE EXCEPTION 'Transfer requires two distinct branches';
  END IF;
  IF v_source.current_quantity<p_quantity THEN RAISE EXCEPTION 'Insufficient source stock'; END IF;
  PERFORM public.apply_inventory_movement(gen_random_uuid(),p_merchant_id,p_source_item_id,'transfer_out',
    p_quantity,p_transfer_id,v_source.branch_id,v_source.cost_price,p_notes,'transfer',now(),NULL);
  PERFORM public.apply_inventory_movement(gen_random_uuid(),p_merchant_id,p_target_item_id,'transfer_in',
    p_quantity,p_transfer_id,v_target.branch_id,v_source.cost_price,p_notes,'transfer',now(),NULL);
  RETURN p_transfer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.transfer_inventory_atomic(uuid,uuid,uuid,uuid,numeric,text) TO anon,authenticated,service_role;
COMMIT;
