ALTER TABLE public.security_policies
ADD COLUMN IF NOT EXISTS require_face_scan BOOLEAN NOT NULL DEFAULT TRUE;
