-- Coupon fields for promotions (POS ↔ Supabase ↔ future web redemption).
BEGIN;

ALTER TABLE public.promotions
  ADD COLUMN IF NOT EXISTS coupon_code varchar(64),
  ADD COLUMN IF NOT EXISTS coupon_max_redemptions integer,
  ADD COLUMN IF NOT EXISTS coupon_expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS idx_promotions_merchant_coupon_code
  ON public.promotions (merchant_id, lower(coupon_code))
  WHERE coupon_code IS NOT NULL AND COALESCE(is_deleted, 0) = 0;

COMMIT;
