-- =========================================================================
-- Migration: Merchant Geo Coordinates for GPS Geofencing
-- Created: 2026-06-28
-- Description: Adds latitude/longitude columns to merchants and branches
--              tables to support GPS-based geofencing for customer web ordering.
--              The customer-order-web uses these coordinates to verify that
--              the customer is physically present at the restaurant before
--              allowing order placement.
-- Status: PENDING
-- =========================================================================

-- Add GPS coordinates to merchants
ALTER TABLE public.merchants
    ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 7) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS longitude DECIMAL(10, 7) DEFAULT NULL;

-- Add GPS coordinates to branches (for multi-location support)
ALTER TABLE public.branches
    ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 7) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS longitude DECIMAL(10, 7) DEFAULT NULL;

-- Add geofence radius (in meters) for configurable proximity checking
ALTER TABLE public.merchants
    ADD COLUMN IF NOT EXISTS geofence_radius_meters INTEGER DEFAULT 50 CHECK (geofence_radius_meters > 0 AND geofence_radius_meters <= 500);

COMMENT ON COLUMN public.merchants.latitude IS 'GPS latitude for geofencing (WGS84)';
COMMENT ON COLUMN public.merchants.longitude IS 'GPS longitude for geofencing (WGS84)';
COMMENT ON COLUMN public.merchants.geofence_radius_meters IS 'Geofence radius in meters (default 50m, max 500m)';
COMMENT ON COLUMN public.branches.latitude IS 'GPS latitude for geofencing (WGS84)';
COMMENT ON COLUMN public.branches.longitude IS 'GPS longitude for geofencing (WGS84)';
