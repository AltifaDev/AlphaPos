-- Prevent fresh/reinstalled clients from manufacturing a second copy of an
-- existing branch before their first server pull completes.
--
-- Historical duplicates are intentionally left untouched by this migration;
-- the trigger protects all future INSERT/UPDATE operations without making the
-- deployment depend on an unrelated tenant cleanup.

CREATE OR REPLACE FUNCTION private.guard_unique_merchant_branch_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    normalized_name text := lower(btrim(NEW.name));
BEGIN
    IF normalized_name = '' THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'branch name must not be empty';
    END IF;

    -- Serialize branch-name creation per merchant so two devices cannot pass
    -- the existence check concurrently.
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.merchant_id::text, 0));

    IF EXISTS (
        SELECT 1
        FROM public.branches b
        WHERE b.merchant_id = NEW.merchant_id
          AND b.id <> NEW.id
          AND lower(btrim(b.name)) = normalized_name
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23505',
            MESSAGE = 'a branch with this name already exists for the merchant',
            CONSTRAINT = 'branches_merchant_normalized_name_key';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_unique_merchant_branch_name ON public.branches;
CREATE TRIGGER trg_guard_unique_merchant_branch_name
    BEFORE INSERT OR UPDATE OF merchant_id, name
    ON public.branches
    FOR EACH ROW
    EXECUTE FUNCTION private.guard_unique_merchant_branch_name();

COMMENT ON FUNCTION private.guard_unique_merchant_branch_name() IS
    'Rejects duplicate normalized branch names inside one merchant, including stale bootstrap UUIDs from older clients.';
