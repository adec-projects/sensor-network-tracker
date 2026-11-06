-- UNDO for supabase/migrations/20261106150000_require_trusted_session.sql
--
-- Removes the "require_trusted_session" policy from every public table,
-- returning the database to exactly how it was before Stage B. Touches nothing
-- else. Run this in the Supabase SQL Editor if anyone is locked out after
-- Stage B. Takes effect immediately; no website change needed.

DO $$
DECLARE
    p record;
BEGIN
    FOR p IN
        SELECT tablename FROM pg_policies
         WHERE schemaname = 'public' AND policyname = 'require_trusted_session'
    LOOP
        EXECUTE format('DROP POLICY require_trusted_session ON public.%I', p.tablename);
        RAISE NOTICE 'removed from: %', p.tablename;
    END LOOP;
END;
$$;

-- Should return zero rows.
SELECT tablename FROM pg_policies
 WHERE schemaname = 'public' AND policyname = 'require_trusted_session';
