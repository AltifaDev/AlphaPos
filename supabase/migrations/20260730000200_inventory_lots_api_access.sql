-- Restore PostgREST access for inventory_lots, which was created after the
-- bulk API privilege migration. The existing merchant-isolation RLS policy
-- remains the tenant-security boundary.

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.inventory_lots
TO anon, authenticated;

ALTER TABLE public.inventory_lots ENABLE ROW LEVEL SECURITY;
