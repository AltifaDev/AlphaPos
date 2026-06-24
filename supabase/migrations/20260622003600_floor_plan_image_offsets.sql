-- Migration 036: Add scale and offset columns to floor_plan_images
-- Date: 2026-06-22
-- Purpose: Sync floor plan layout transforms (scale, offset_x, offset_y) so other devices render them identically.

ALTER TABLE public.floor_plan_images
    ADD COLUMN IF NOT EXISTS scale DOUBLE PRECISION DEFAULT 1.0,
    ADD COLUMN IF NOT EXISTS offset_x DOUBLE PRECISION DEFAULT 0.0,
    ADD COLUMN IF NOT EXISTS offset_y DOUBLE PRECISION DEFAULT 0.0;
