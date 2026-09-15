-- Add floor-plan visual scale for restaurant tables (corner-handle resize in edit layout).
ALTER TABLE public.restaurant_tables
    ADD COLUMN IF NOT EXISTS layout_scale DOUBLE PRECISION NOT NULL DEFAULT 1.0;

COMMENT ON COLUMN public.restaurant_tables.layout_scale IS
    'Floor-plan display scale (1.0 = default). Used by POS edit-layout corner resize.';
