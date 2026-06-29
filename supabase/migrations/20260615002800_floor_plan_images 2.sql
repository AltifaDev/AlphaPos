-- ==============================================================================
-- Migration 025: Floor Plan Images
-- Date: 2026-06-18
-- Purpose: Store floor plan background image metadata per merchant per floor.
--          Image binary is stored locally on device; only filename + metadata synced.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.floor_plan_images (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    floor INTEGER NOT NULL,
    image_filename TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    is_deleted BOOLEAN DEFAULT false,
    UNIQUE (merchant_id, floor)
);

ALTER TABLE public.floor_plan_images ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'floor_plan_images'
        AND policyname = 'floor_plan_images_merchant_access'
    ) THEN
        CREATE POLICY "floor_plan_images_merchant_access"
            ON public.floor_plan_images
            FOR ALL
            USING (merchant_id = get_active_merchant_id())
            WITH CHECK (merchant_id = get_active_merchant_id());
    END IF;
END $$;

-- Enable Realtime
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND schemaname = 'public'
            AND tablename = 'floor_plan_images'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.floor_plan_images;
        END IF;
    END IF;
END $$;
