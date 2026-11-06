-- get_admin_contacts: names + emails of the active app administrators.
--
-- Shown on the "Can't access your authenticator app?" help panel, so someone
-- who lost their phone knows exactly who can reset their MFA. Callable by any
-- signed-in user (they have already passed the password step); not by the
-- public. SECURITY DEFINER so it keeps working even if table-level rules later
-- require the authenticator step for ordinary reads.
--
-- Safe to run more than once.

CREATE OR REPLACE FUNCTION public.get_admin_contacts()
RETURNS TABLE (name text, email text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT DISTINCT coalesce(nullif(p.name, ''), a.email) AS name, a.email
      FROM public.allowed_emails a
      LEFT JOIN public.profiles p ON lower(p.email) = lower(a.email)
     WHERE a.role = 'admin'
       AND (a.status IS NULL OR a.status = 'active')
     ORDER BY 1;
$$;

REVOKE ALL ON FUNCTION public.get_admin_contacts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_contacts() TO authenticated;
