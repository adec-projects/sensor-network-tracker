-- Fix: get_admin_contacts listed admins who were on the allowlist but had never
-- created an account (e.g. invited but not signed up yet). Those people can't
-- sign in, so they can't reset anyone's authenticator. Now only admins with a
-- real account are listed.
--
-- Safe to run more than once.

CREATE OR REPLACE FUNCTION public.get_admin_contacts()
RETURNS TABLE (name text, email text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT DISTINCT coalesce(nullif(p.name, ''), a.email) AS name, a.email
      FROM public.allowed_emails a
      JOIN auth.users u          ON lower(u.email) = lower(a.email)   -- has an account
      LEFT JOIN public.profiles p ON p.id = u.id
     WHERE a.role = 'admin'
       AND (a.status IS NULL OR a.status = 'active')
     ORDER BY 1;
$$;

REVOKE ALL ON FUNCTION public.get_admin_contacts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_contacts() TO authenticated;
