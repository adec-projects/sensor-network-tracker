-- STAGE A of database-enforced sign-in rules.
--
-- session_is_trusted(): may the current login see app data?
--
-- Until now, MFA and "archived user" were enforced only by the website's
-- JavaScript. The database answered any logged-in request, so a password alone
-- (or an archived user's old password) could read data by calling the database
-- directly. This function is the single, server-side answer. Stage B
-- (20261106150000_require_trusted_session.sql) attaches it to every table.
--
-- A login is trusted when BOTH:
--   1. its email is on the allowlist and active (not archived/revoked), AND
--   2. one of:
--        - it completed the authenticator step (aal2), or
--        - an admin has switched "Require MFA" off (app_settings.mfa_required = 'false'), or
--        - the user has no finished authenticator yet (first-time setup screen).
--          A user can't remove a finished authenticator without already being
--          at aal2, so this can't be used to skip the code.
--
-- Mirrors the app's existing rules exactly (app.js: checkMfaAndProceed, and the
-- archived check in enterApp). Creating this function changes NOTHING by itself.
-- Safe to run more than once.

CREATE OR REPLACE FUNCTION public.session_is_trusted()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT
        auth.uid() IS NOT NULL
        AND EXISTS (
            SELECT 1
              FROM public.allowed_emails a
              JOIN auth.users u ON lower(u.email) = lower(a.email)
             WHERE u.id = auth.uid()
               AND (a.status IS NULL OR a.status = 'active')
        )
        AND (
            coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
            OR coalesce((SELECT s.value FROM public.app_settings s WHERE s.key = 'mfa_required'), 'true') = 'false'
            OR NOT EXISTS (
                SELECT 1 FROM auth.mfa_factors f
                 WHERE f.user_id = auth.uid() AND f.status = 'verified'
            )
        );
$$;

REVOKE ALL ON FUNCTION public.session_is_trusted() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.session_is_trusted() TO anon, authenticated;
