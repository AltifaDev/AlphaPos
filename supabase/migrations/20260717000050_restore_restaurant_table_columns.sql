ALTER TABLE public.restaurant_tables
    ADD COLUMN IF NOT EXISTS is_round boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS table_shape varchar(30),
    ADD COLUMN IF NOT EXISTS zone varchar(100);
