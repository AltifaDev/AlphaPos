-- Persist table join/split groups across devices.
-- Child rows point at the group leader via joined_parent_table_id (NULL = not joined).

ALTER TABLE public.restaurant_tables
    ADD COLUMN IF NOT EXISTS joined_parent_table_id UUID
        REFERENCES public.restaurant_tables(id) ON DELETE SET NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'restaurant_tables_joined_parent_not_self'
          AND conrelid = 'public.restaurant_tables'::regclass
    ) THEN
        ALTER TABLE public.restaurant_tables
            ADD CONSTRAINT restaurant_tables_joined_parent_not_self
            CHECK (
                joined_parent_table_id IS NULL
                OR joined_parent_table_id <> id
            );
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_restaurant_tables_joined_parent
    ON public.restaurant_tables(joined_parent_table_id)
    WHERE joined_parent_table_id IS NOT NULL;

COMMENT ON COLUMN public.restaurant_tables.joined_parent_table_id IS
    'Group leader table id when this table is joined as a child; NULL when not joined.';
