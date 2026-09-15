-- Restaurant table numbers are reusable across branches and dining areas.
-- Identity and conflict resolution must never be merchant-wide.
ALTER TABLE public.restaurant_tables
    DROP CONSTRAINT IF EXISTS unique_merchant_table_number;

ALTER TABLE public.restaurant_tables
    ALTER COLUMN branch_id SET NOT NULL,
    ALTER COLUMN dining_area_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS restaurant_tables_area_number_key
    ON public.restaurant_tables (merchant_id, branch_id, dining_area_id, table_number);

CREATE INDEX IF NOT EXISTS idx_restaurant_tables_branch_area_active
    ON public.restaurant_tables (merchant_id, branch_id, dining_area_id)
    WHERE NOT is_deleted;

NOTIFY pgrst, 'reload schema';
