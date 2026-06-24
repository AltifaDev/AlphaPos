-- ==============================================================================
-- Migration 009: Restaurant Walls for Zone Partition Lines
-- Date: 2026-06-12
-- Purpose: Enable partition line sync between iPad (SwiftData) and Web (Supabase)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.restaurant_walls (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    floor INTEGER NOT NULL,
    type_string VARCHAR(50) NOT NULL DEFAULT 'straight',
    start_x DOUBLE PRECISION NOT NULL,
    start_y DOUBLE PRECISION NOT NULL,
    end_x DOUBLE PRECISION NOT NULL,
    end_y DOUBLE PRECISION NOT NULL,
    control_x DOUBLE PRECISION,
    control_y DOUBLE PRECISION,
    stroke_width DOUBLE PRECISION NOT NULL DEFAULT 10.0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    is_deleted BOOLEAN DEFAULT false
);

ALTER TABLE public.restaurant_walls ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'restaurant_walls' 
        AND policyname = 'restaurant_walls_merchant_access'
    ) THEN
        CREATE POLICY "restaurant_walls_merchant_access" 
            ON public.restaurant_walls
            FOR ALL
            USING (merchant_id = get_active_merchant_id())
            WITH CHECK (merchant_id = get_active_merchant_id());
    END IF;
END $$;

-- Enable Realtime for restaurant_walls if publication exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' 
            AND schemaname = 'public' 
            AND tablename = 'restaurant_walls'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_walls;
        END IF;
    END IF;
END $$;
