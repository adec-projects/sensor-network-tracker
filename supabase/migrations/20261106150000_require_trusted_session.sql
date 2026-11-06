-- STAGE B: make the database enforce sign-in rules on every table.
--
-- Adds ONE extra policy named "require_trusted_session" to every table in the
-- public schema that has Row Level Security on. It is RESTRICTIVE: it does not
-- replace the existing policies, it is checked IN ADDITION to them. A request
-- now needs (existing rules) AND (session_is_trusted() = true).
--
-- Requires STAGE A (public.session_is_trusted) to exist first.
-- Applies to signed-in users only ("TO authenticated"). Database jobs, the
-- Supabase dashboard, and SECURITY DEFINER functions are unaffected.
--
-- UNDO: run supabase/rollback/undo_require_trusted_session.sql
-- Safe to run more than once (drops and re-creates its own policy only).

DO $$
DECLARE
    t record;
BEGIN
    FOR t IN
        SELECT c.relname AS tbl
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relkind = 'r'
           AND c.relrowsecurity
         ORDER BY c.relname
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS require_trusted_session ON public.%I', t.tbl);
        IF t.tbl = 'profiles' THEN
            -- profiles has UPDATE policies that look up profiles inside
            -- themselves; a sub-query here would trip Postgres's "infinite
            -- recursion" guard (see 20261106190000). Call the function directly.
            EXECUTE 'CREATE POLICY require_trusted_session ON public.profiles AS RESTRICTIVE FOR ALL TO authenticated '
                    'USING (public.session_is_trusted()) WITH CHECK (public.session_is_trusted())';
        ELSE
            -- "(SELECT ...)" makes Postgres evaluate the check once per request
            -- instead of once per row.
            EXECUTE format(
                'CREATE POLICY require_trusted_session ON public.%I AS RESTRICTIVE FOR ALL TO authenticated '
                'USING ((SELECT public.session_is_trusted())) WITH CHECK ((SELECT public.session_is_trusted()))',
                t.tbl);
        END IF;
        RAISE NOTICE 'protected: %', t.tbl;
    END LOOP;
END;
$$;

-- Show the result: every table, and whether it now has the rule.
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_on,
       EXISTS (SELECT 1 FROM pg_policies p
                WHERE p.schemaname = 'public' AND p.tablename = c.relname
                  AND p.policyname = 'require_trusted_session') AS protected
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
 ORDER BY 1;
