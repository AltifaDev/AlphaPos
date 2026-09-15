-- Prep recipe sync uses the authenticated merchant JWT through PostgREST.
-- The tables were created with RLS policies but authenticated CRUD grants were
-- missing, causing otherwise healthy online sync cycles to report Partial Sync.

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.prep_recipes,
         public.prep_recipe_components,
         public.prep_production_batches
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.prep_recipes,
         public.prep_recipe_components,
         public.prep_production_batches
TO service_role;
