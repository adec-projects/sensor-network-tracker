-- Fix: "infinite recursion detected in policy for relation profiles" when an
-- admin changes someone's role (and in the app's sign-in role sync).
--
-- Cause: two existing UPDATE policies on profiles look up profiles inside
-- themselves ("Admins can update any profile", "Users can update own profile").
-- Postgres allows that only if the inner lookup's own policies contain no
-- sub-query. Stage B (20261106150000) added require_trusted_session written as
-- "(SELECT public.session_is_trusted())", which IS a sub-query, so the inner
-- lookup tripped Postgres's recursion guard.
--
-- Fix: on profiles only, call the function directly (no sub-query). Same rule,
-- same protection. Postgres then evaluates it per row instead of once per
-- request, which is negligible for this small table. Other tables keep the
-- faster form.
--
-- Safe to run more than once.

DROP POLICY IF EXISTS require_trusted_session ON public.profiles;

CREATE POLICY require_trusted_session ON public.profiles
    AS RESTRICTIVE
    FOR ALL
    TO authenticated
    USING (public.session_is_trusted())
    WITH CHECK (public.session_is_trusted());

-- Confirm: should show the policy WITHOUT "SELECT" in the using/with_check.
SELECT policyname, permissive, cmd, qual AS using_clause, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'profiles'
   AND policyname = 'require_trusted_session';
