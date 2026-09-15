-- Customer web: branch-authoritative session claims, atomic/idempotent writes.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='customer_web') THEN CREATE ROLE customer_web NOLOGIN; END IF;
END $$;
GRANT customer_web TO authenticator;
GRANT USAGE ON SCHEMA public TO customer_web;

ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
ALTER TABLE public.modifiers ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.customer_order_operations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  table_session_id UUID NOT NULL REFERENCES public.table_sessions(id) ON DELETE CASCADE,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(table_session_id, idempotency_key)
);
ALTER TABLE public.customer_order_operations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_order_operations_scope ON public.customer_order_operations;
CREATE POLICY customer_order_operations_scope ON public.customer_order_operations AS RESTRICTIVE
FOR SELECT TO anon, authenticated
USING (merchant_id=public.get_active_merchant_id() AND branch_id=public.get_active_branch_id());

CREATE OR REPLACE FUNCTION public.require_customer_session()
RETURNS public.table_sessions
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE
  c JSONB := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  s public.table_sessions;
BEGIN
  IF c->>'token_use' IS DISTINCT FROM 'customer_session' OR c->>'table_session_id' IS NULL
     OR c->>'merchant_id' IS NULL OR c->>'branch_id' IS NULL OR c->>'table_number' IS NULL THEN
    RAISE EXCEPTION 'customer_session_required' USING ERRCODE='28000';
  END IF;
  SELECT * INTO s FROM public.table_sessions
   WHERE id=(c->>'table_session_id')::uuid AND merchant_id=(c->>'merchant_id')::uuid
     AND branch_id=(c->>'branch_id')::uuid AND table_number=c->>'table_number'
     AND is_active=1 AND ended_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'customer_session_closed' USING ERRCODE='28000'; END IF;
  RETURN s;
END $$;
REVOKE ALL ON FUNCTION public.require_customer_session() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.create_customer_order(
  p_order JSONB, p_items JSONB, p_modifiers JSONB DEFAULT '[]'::jsonb
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  s public.table_sessions := public.require_customer_session();
  oid UUID := (p_order->>'id')::uuid;
  ikey TEXT := NULLIF(p_order->>'idempotency_key','');
  rhash TEXT := encode(extensions.digest(convert_to(COALESCE(p_items,'[]'::jsonb)::text || COALESCE(p_modifiers,'[]'::jsonb)::text,'UTF8'), 'sha256'),'hex');
  op public.customer_order_operations;
  line JSONB; mod JSONB; menu_id TEXT; item_uuid UUID; qty INT;
  menu_price NUMERIC; menu_name TEXT; mod_sum NUMERIC; client_unit NUMERIC;
  subtotal NUMERIC := 0; discount NUMERIC := 0; service NUMERIC := 0; tax NUMERIC := 0; total NUMERIC := 0;
  service_rate NUMERIC := 0; tax_rate NUMERIC := 0; tax_type TEXT := 'inclusive';
BEGIN
  IF oid IS NULL OR ikey IS NULL OR length(ikey)>100 THEN RAISE EXCEPTION 'invalid_order_identity'; END IF;
  IF jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 OR jsonb_array_length(p_items)>100 THEN RAISE EXCEPTION 'invalid_order_items'; END IF;

  SELECT * INTO op FROM public.customer_order_operations WHERE table_session_id=s.id AND idempotency_key=ikey;
  IF FOUND THEN
    IF op.request_hash<>rhash THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='23505'; END IF;
    RETURN op.order_id;
  END IF;
  INSERT INTO public.customer_order_operations(merchant_id,branch_id,table_session_id,idempotency_key,request_hash)
  VALUES(s.merchant_id,s.branch_id,s.id,ikey,rhash);

  FOR line IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    menu_id := NULLIF(line->>'item_id',''); item_uuid := (line->>'id')::uuid;
    qty := GREATEST(1,LEAST(COALESCE((line->>'quantity')::int,1),99));
    SELECT price,name INTO menu_price,menu_name FROM public.menu_items
      WHERE id=menu_id AND merchant_id=s.merchant_id AND (branch_id IS NULL OR branch_id=s.branch_id)
        AND COALESCE(is_available,true) AND NOT COALESCE(is_deleted,false);
    IF menu_price IS NULL THEN RAISE EXCEPTION 'menu_item_unavailable:%',menu_id; END IF;
    SELECT COALESCE(sum(m.extra_price),0) INTO mod_sum
      FROM jsonb_array_elements(COALESCE(p_modifiers,'[]'::jsonb)) x
      JOIN public.modifiers m ON m.id=(x.value->>'modifier_id')::uuid
       AND m.merchant_id=s.merchant_id AND (m.branch_id IS NULL OR m.branch_id=s.branch_id)
       AND COALESCE(m.is_available,true) AND NOT COALESCE(m.is_deleted,false)
      WHERE (x.value->>'order_item_id')::uuid=item_uuid;
    client_unit:=COALESCE((line->>'price')::numeric,-1);
    IF abs(client_unit-(menu_price+mod_sum))>0.05 THEN RAISE EXCEPTION 'price_mismatch:%',menu_id; END IF;
    subtotal:=subtotal+(menu_price+mod_sum)*qty;
  END LOOP;

  SELECT COALESCE(m.service_charge_rate,0),COALESCE(m.tax_rate,0),COALESCE(m.tax_type,'inclusive')
    INTO service_rate,tax_rate,tax_type FROM public.merchants m WHERE m.id=s.merchant_id;
  discount:=LEAST(GREATEST(COALESCE((p_order->>'discount')::numeric,0),0),subtotal);
  service:=round((subtotal-discount)*service_rate/100,2);
  IF lower(tax_type)='exclusive' THEN
    tax:=round((subtotal-discount+service)*tax_rate/100,2); total:=subtotal-discount+service+tax;
  ELSE
    total:=subtotal-discount+service;
    tax:=CASE WHEN tax_rate>0 THEN round(total*tax_rate/(100+tax_rate),2) ELSE 0 END;
  END IF;

  INSERT INTO public.orders(id,order_number,table_number,total,subtotal,tax,service_charge,discount,status,
    order_source,is_staff_confirmed,session_token,guest_count,merchant_id,branch_id,created_at)
  VALUES(oid,COALESCE(NULLIF(p_order->>'order_number',''),'WEB-'||substr(oid::text,1,8)),s.table_number,total,subtotal,tax,service,discount,
    'pending','web',false,s.session_token,GREATEST(1,LEAST(COALESCE((p_order->>'guest_count')::int,1),100)),s.merchant_id,s.branch_id,now());

  FOR line IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    item_uuid:=(line->>'id')::uuid; menu_id:=line->>'item_id'; qty:=GREATEST(1,LEAST(COALESCE((line->>'quantity')::int,1),99));
    SELECT price,name INTO menu_price,menu_name FROM public.menu_items WHERE id=menu_id AND merchant_id=s.merchant_id;
    SELECT COALESCE(sum(m.extra_price),0) INTO mod_sum FROM jsonb_array_elements(COALESCE(p_modifiers,'[]'::jsonb)) x
      JOIN public.modifiers m ON m.id=(x.value->>'modifier_id')::uuid WHERE (x.value->>'order_item_id')::uuid=item_uuid;
    INSERT INTO public.order_items(id,order_id,item_name,quantity,price,status,item_id,merchant_id,branch_id,notes)
    VALUES(item_uuid,oid,menu_name,qty,menu_price+mod_sum,'pending',menu_id,s.merchant_id,s.branch_id,NULLIF(line->>'notes',''));
  END LOOP;
  FOR mod IN SELECT value FROM jsonb_array_elements(COALESCE(p_modifiers,'[]'::jsonb)) LOOP
    INSERT INTO public.order_item_modifiers(id,order_item_id,modifier_id,price,merchant_id)
    SELECT (mod->>'id')::uuid,(mod->>'order_item_id')::uuid,m.id,m.extra_price,s.merchant_id FROM public.modifiers m
     WHERE m.id=(mod->>'modifier_id')::uuid AND m.merchant_id=s.merchant_id AND (m.branch_id IS NULL OR m.branch_id=s.branch_id);
  END LOOP;
  UPDATE public.customer_order_operations SET order_id=oid WHERE table_session_id=s.id AND idempotency_key=ikey;
  INSERT INTO public.sync_outbox(merchant_id,idempotency_key,job_type,payload)
  VALUES(s.merchant_id,'customer-order:'||oid,'customer_order.created',jsonb_build_object('order_id',oid,'branch_id',s.branch_id,'session_id',s.id))
  ON CONFLICT(merchant_id,idempotency_key) DO NOTHING;
  RETURN oid;
END $$;
REVOKE ALL ON FUNCTION public.create_customer_order(JSONB,JSONB,JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_customer_order(JSONB,JSONB,JSONB) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_customer_order(JSONB,JSONB,JSONB) TO customer_web;

CREATE OR REPLACE FUNCTION public.create_customer_service_request(p_request_type TEXT,p_idempotency_key TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.table_sessions:=public.require_customer_session(); rid UUID;
BEGIN
  IF p_request_type NOT IN ('Bill (Cash)','Bill (Card)','Bill (QR)','Ice/Water','Extra Utensils','General Help') THEN RAISE EXCEPTION 'invalid_request_type'; END IF;
  SELECT id INTO rid FROM public.service_requests WHERE merchant_id=s.merchant_id AND branch_id=s.branch_id
    AND table_number=s.table_number AND request_type=p_request_type AND status='pending' AND created_at>now()-interval '30 seconds' LIMIT 1;
  IF rid IS NOT NULL THEN RETURN rid; END IF;
  rid:=gen_random_uuid();
  INSERT INTO public.service_requests(id,merchant_id,branch_id,table_number,request_type,status,created_at)
  VALUES(rid,s.merchant_id,s.branch_id,s.table_number,p_request_type,'pending',now());
  INSERT INTO public.sync_outbox(merchant_id,idempotency_key,job_type,payload)
  VALUES(s.merchant_id,'customer-request:'||s.id||':'||p_idempotency_key,'customer_service_request.created',jsonb_build_object('request_id',rid,'branch_id',s.branch_id))
  ON CONFLICT(merchant_id,idempotency_key) DO NOTHING;
  RETURN rid;
END $$;
REVOKE ALL ON FUNCTION public.create_customer_service_request(TEXT,TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_customer_service_request(TEXT,TEXT) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_customer_service_request(TEXT,TEXT) TO customer_web;

CREATE OR REPLACE FUNCTION public.update_customer_order_item_note(p_order_item_id UUID,p_note TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.table_sessions:=public.require_customer_session();
BEGIN
  IF length(COALESCE(p_note,''))>500 THEN RAISE EXCEPTION 'note_too_long'; END IF;
  UPDATE public.order_items i SET customer_note=NULLIF(trim(p_note),'')
   FROM public.orders o WHERE i.id=p_order_item_id AND o.id=i.order_id
    AND o.merchant_id=s.merchant_id AND o.branch_id=s.branch_id AND o.session_token=s.session_token
    AND o.status NOT IN ('completed','cancelled');
  IF NOT FOUND THEN RAISE EXCEPTION 'order_item_not_editable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.update_customer_order_item_note(UUID,TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_customer_order_item_note(UUID,TEXT) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_customer_order_item_note(UUID,TEXT) TO customer_web;

-- Least-privilege read surface for browser/Reatime. The customer_web role is
-- deliberately not a member of anon/authenticated and cannot call staff RPCs.
GRANT SELECT ON public.merchants,public.branches,public.restaurant_tables,public.table_sessions,
  public.menu_items,public.modifier_groups,public.modifiers,public.menu_item_modifier_groups,
  public.promotions,public.orders,public.order_items,public.order_item_modifiers TO customer_web;

DROP POLICY IF EXISTS customer_web_merchant_read ON public.merchants;
CREATE POLICY customer_web_merchant_read ON public.merchants AS RESTRICTIVE FOR SELECT TO customer_web
USING (id=public.get_active_merchant_id());
DROP POLICY IF EXISTS customer_web_branch_read ON public.branches;
CREATE POLICY customer_web_branch_read ON public.branches AS RESTRICTIVE FOR SELECT TO customer_web
USING (id=public.get_active_branch_id() AND merchant_id=public.get_active_merchant_id());
DROP POLICY IF EXISTS customer_web_table_read ON public.restaurant_tables;
CREATE POLICY customer_web_table_read ON public.restaurant_tables AS RESTRICTIVE FOR SELECT TO customer_web
USING (merchant_id=public.get_active_merchant_id() AND branch_id=public.get_active_branch_id()
  AND table_number=current_setting('request.jwt.claims',true)::jsonb->>'table_number');
DROP POLICY IF EXISTS customer_web_session_read ON public.table_sessions;
CREATE POLICY customer_web_session_read ON public.table_sessions AS RESTRICTIVE FOR SELECT TO customer_web
USING (id=(current_setting('request.jwt.claims',true)::jsonb->>'table_session_id')::uuid
  AND merchant_id=public.get_active_merchant_id() AND branch_id=public.get_active_branch_id());
DROP POLICY IF EXISTS customer_web_menu_read ON public.menu_items;
CREATE POLICY customer_web_menu_read ON public.menu_items AS RESTRICTIVE FOR SELECT TO customer_web
USING (merchant_id=public.get_active_merchant_id() AND (branch_id IS NULL OR branch_id=public.get_active_branch_id())
  AND COALESCE(is_available,true) AND NOT COALESCE(is_deleted,false));
DROP POLICY IF EXISTS customer_web_modifier_read ON public.modifiers;
CREATE POLICY customer_web_modifier_read ON public.modifiers AS RESTRICTIVE FOR SELECT TO customer_web
USING (merchant_id=public.get_active_merchant_id() AND (branch_id IS NULL OR branch_id=public.get_active_branch_id())
  AND COALESCE(is_available,true) AND NOT COALESCE(is_deleted,false));
DROP POLICY IF EXISTS customer_web_modifier_group_read ON public.modifier_groups;
CREATE POLICY customer_web_modifier_group_read ON public.modifier_groups AS RESTRICTIVE FOR SELECT TO customer_web
USING (merchant_id=public.get_active_merchant_id() AND NOT COALESCE(is_deleted,false));
DROP POLICY IF EXISTS customer_web_modifier_link_read ON public.menu_item_modifier_groups;
CREATE POLICY customer_web_modifier_link_read ON public.menu_item_modifier_groups AS RESTRICTIVE FOR SELECT TO customer_web
USING (merchant_id=public.get_active_merchant_id() AND NOT COALESCE(is_deleted,false));
DROP POLICY IF EXISTS customer_web_promotion_read ON public.promotions;
CREATE POLICY customer_web_promotion_read ON public.promotions AS RESTRICTIVE FOR SELECT TO customer_web
USING (merchant_id=public.get_active_merchant_id()
  AND COALESCE(is_active::text,'1') IN ('1','true')
  AND COALESCE(is_deleted::text,'0') IN ('0','false'));
DROP POLICY IF EXISTS customer_web_order_read ON public.orders;
CREATE POLICY customer_web_order_read ON public.orders AS RESTRICTIVE FOR SELECT TO customer_web
USING (merchant_id=public.get_active_merchant_id() AND branch_id=public.get_active_branch_id()
  AND session_token=(SELECT session_token FROM public.table_sessions WHERE id=(current_setting('request.jwt.claims',true)::jsonb->>'table_session_id')::uuid));
DROP POLICY IF EXISTS customer_web_order_item_read ON public.order_items;
CREATE POLICY customer_web_order_item_read ON public.order_items AS RESTRICTIVE FOR SELECT TO customer_web
USING (EXISTS (SELECT 1 FROM public.orders o WHERE o.id=order_items.order_id
  AND o.merchant_id=public.get_active_merchant_id() AND o.branch_id=public.get_active_branch_id()
  AND o.session_token=(SELECT session_token FROM public.table_sessions WHERE id=(current_setting('request.jwt.claims',true)::jsonb->>'table_session_id')::uuid)));
DROP POLICY IF EXISTS customer_web_order_modifier_read ON public.order_item_modifiers;
CREATE POLICY customer_web_order_modifier_read ON public.order_item_modifiers AS RESTRICTIVE FOR SELECT TO customer_web
USING (EXISTS (SELECT 1 FROM public.order_items i JOIN public.orders o ON o.id=i.order_id
  WHERE i.id=order_item_modifiers.order_item_id AND o.merchant_id=public.get_active_merchant_id()
    AND o.branch_id=public.get_active_branch_id()
    AND o.session_token=(SELECT session_token FROM public.table_sessions WHERE id=(current_setting('request.jwt.claims',true)::jsonb->>'table_session_id')::uuid)));
