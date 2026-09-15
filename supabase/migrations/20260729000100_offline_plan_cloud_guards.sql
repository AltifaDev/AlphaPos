-- Offline subscriptions cannot expose web ordering or cloud staff-device access.
BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_offline_plan_merchant_features()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.subscription_tier IN ('offline_perpetual', 'offline_subscription') THEN
    NEW.is_web_ordering_enabled := false;

    IF TG_OP = 'UPDATE'
       AND OLD.subscription_tier IS DISTINCT FROM NEW.subscription_tier THEN
      UPDATE public.merchant_devices
      SET is_trusted = false, updated_at = now()
      WHERE merchant_id = NEW.id;

      DELETE FROM public.device_pairing_tokens
      WHERE merchant_id = NEW.id AND is_used = false;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_offline_plan_merchant_features ON public.merchants;
CREATE TRIGGER trg_offline_plan_merchant_features
BEFORE INSERT OR UPDATE OF subscription_tier, is_web_ordering_enabled
ON public.merchants
FOR EACH ROW EXECUTE FUNCTION public.enforce_offline_plan_merchant_features();

CREATE OR REPLACE FUNCTION public.reject_offline_plan_cloud_channel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = NEW.merchant_id
      AND m.subscription_tier IN ('offline_perpetual', 'offline_subscription')
  ) THEN
    RAISE EXCEPTION 'cloud channel unavailable for offline subscription'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_offline_pairing ON public.device_pairing_tokens;
CREATE TRIGGER trg_reject_offline_pairing
BEFORE INSERT OR UPDATE ON public.device_pairing_tokens
FOR EACH ROW EXECUTE FUNCTION public.reject_offline_plan_cloud_channel();

CREATE OR REPLACE FUNCTION public.reject_offline_plan_remote_orders()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.order_source IN ('web', 'staff') AND EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = NEW.merchant_id
      AND m.subscription_tier IN ('offline_perpetual', 'offline_subscription')
  ) THEN
    RAISE EXCEPTION 'remote orders unavailable for offline subscription'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_offline_remote_orders ON public.orders;
CREATE TRIGGER trg_reject_offline_remote_orders
BEFORE INSERT OR UPDATE OF order_source ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.reject_offline_plan_remote_orders();

COMMIT;
