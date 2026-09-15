-- Fix: migration 20260713000300 revoked INSERT/UPDATE/DELETE on
-- public.orders, public.order_items, public.order_item_modifiers FROM anon.
-- The iPad/iPhone apps authenticate with the merchant JWT whose Postgres role
-- is `anon` (see supabase/functions/issue-merchant-token/index.ts, role: "anon",
-- and refresh-token/index.ts). Without these write privileges the apps get
-- "permission denied for table orders" (SQLSTATE 42501) when updating order
-- status / running the order migration, so the iPad table status never refreshes
-- after a web order and the order migration is skipped.
--
-- This is safe: a true anonymous browser (no merchant JWT) still cannot write,
-- because RLS policies evaluate get_merchant_id() from the JWT claim, which is
-- NULL without a merchant JWT, so every write is denied by RLS. Only requests
-- carrying a valid merchant JWT (the staff/iPad apps) can actually write.
GRANT INSERT, UPDATE, DELETE ON public.orders TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.order_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.order_item_modifiers TO anon, authenticated;
