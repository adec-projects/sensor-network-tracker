-- SECURITY FIX: privilege escalation via profiles.role.
--
-- The "Users can update own profile" policy had USING (auth.uid() = id) but NO
-- WITH CHECK, so any authenticated user could set their own profiles.role to
-- 'admin' from the browser and pass every admin-gated RLS check. This:
--   1. Tightens that policy so a user can update their own profile but CANNOT
--      change their own role.
--   2. Adds sync_my_role(): a SECURITY DEFINER RPC that syncs the caller's
--      profiles.role from the admin-controlled allowed_emails table (the real
--      source of truth). A user cannot escalate with it; it only ever sets the
--      role an admin already assigned them. The app calls this in place of the
--      old direct client write.
--   3. One-time backfill: fixes any profiles whose role had already drifted
--      from allowed_emails.
--
-- Admins still change roles via the existing "Admins can update any profile"
-- policy (and changeUserRole, which writes allowed_emails + profiles).

-- 1. Tighten the self-update policy: own profile yes, own role no.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (
        auth.uid() = id
        AND role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
    );

-- 2. Trusted role sync (caller's own role, from allowed_emails only).
CREATE OR REPLACE FUNCTION public.sync_my_role()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_role text;
BEGIN
    SELECT ae.role INTO target_role
    FROM allowed_emails ae
    WHERE lower(ae.email) = lower((SELECT email FROM auth.users WHERE id = auth.uid()))
      AND (ae.status IS NULL OR ae.status = 'active');
    IF target_role IS NOT NULL THEN
        UPDATE profiles SET role = target_role WHERE id = auth.uid();
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_my_role() TO authenticated;

-- 3. One-time backfill of already-drifted profile roles.
UPDATE public.profiles p
SET role = ae.role
FROM public.allowed_emails ae
WHERE lower(p.email) = lower(ae.email)
  AND (ae.status IS NULL OR ae.status = 'active')
  AND p.role IS DISTINCT FROM ae.role;

NOTIFY pgrst, 'reload schema';
