ALTER TABLE public.table_layout_presets
    ADD COLUMN IF NOT EXISTS schema_version INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS bg_image_checksum TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS table_layout_presets_scope_name_key
    ON public.table_layout_presets (merchant_id, branch_id, floor, lower(name))
    WHERE is_deleted = false;

ALTER TABLE public.floor_plan_images
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE;

ALTER TABLE public.floor_plan_images
    DROP CONSTRAINT IF EXISTS floor_plan_images_merchant_id_floor_key;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'floor_plan_images_merchant_branch_floor_key'
          AND conrelid = 'public.floor_plan_images'::regclass
    ) THEN
        ALTER TABLE public.floor_plan_images
            ADD CONSTRAINT floor_plan_images_merchant_branch_floor_key
            UNIQUE (merchant_id, branch_id, floor);
    END IF;
END
$$;
