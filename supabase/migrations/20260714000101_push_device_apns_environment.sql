ALTER TABLE public.push_devices
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'push_devices_environment_check'
      AND conrelid = 'public.push_devices'::regclass
  ) THEN
    ALTER TABLE public.push_devices
      ADD CONSTRAINT push_devices_environment_check
      CHECK (environment IN ('sandbox', 'production'));
  END IF;
END;
$$;
