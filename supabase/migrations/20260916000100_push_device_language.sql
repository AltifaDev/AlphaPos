-- Keep the language selected in the Staff app with its push registration.
ALTER TABLE public.push_devices
  ADD COLUMN IF NOT EXISTS language_code TEXT NOT NULL DEFAULT 'en';

ALTER TABLE public.push_devices
  DROP CONSTRAINT IF EXISTS push_devices_language_code_check;

ALTER TABLE public.push_devices
  ADD CONSTRAINT push_devices_language_code_check
  CHECK (language_code IN ('en', 'th', 'lo'));
