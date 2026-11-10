-- Self-service authenticator reset, and a tighter admin reset.
--
-- 1. reset_my_mfa(current_password)  (new)
--    Lets any signed-in user remove their OWN authenticator (e.g. switching to a
--    new phone) from Settings > User Management > "Reset MFA" on their own row.
--    Requires a fully trusted session AND the current password, so someone at an
--    unlocked computer can't strip the authenticator off. The app then signs the
--    user out; at next sign-in they are walked through setting up a new one.
--
-- 2. admin_reset_mfa(target_email)  (tightened)
--    Still admin-only, now also requires the admin to be fully signed in
--    (password + code) and can't target yourself (use reset_my_mfa, which checks
--    your password).
--
-- Safe to run more than once.

CREATE OR REPLACE FUNCTION public.reset_my_mfa(current_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
    uid    uuid := auth.uid();
    stored text;
BEGIN
    IF uid IS NULL OR NOT public.session_is_trusted() THEN
        RAISE EXCEPTION 'You must be fully signed in to reset your authenticator.';
    END IF;

    SELECT encrypted_password INTO stored FROM auth.users WHERE id = uid;
    IF stored IS NULL OR stored = ''
       OR stored <> extensions.crypt(coalesce(current_password, ''), stored) THEN
        RAISE EXCEPTION 'Current password is incorrect.';
    END IF;

    DELETE FROM auth.mfa_factors WHERE user_id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.reset_my_mfa(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_my_mfa(text) TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_reset_mfa(target_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    target_id uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
       OR NOT public.session_is_trusted() THEN
        RAISE EXCEPTION 'Only a signed-in administrator can reset MFA.';
    END IF;
    SELECT id INTO target_id FROM auth.users WHERE lower(email) = lower(target_email);
    IF target_id IS NULL THEN
        RAISE EXCEPTION 'No user with that email';
    END IF;
    IF target_id = auth.uid() THEN
        RAISE EXCEPTION 'To reset your own authenticator, use Reset MFA on your own row (it asks for your password).';
    END IF;
    DELETE FROM auth.mfa_factors WHERE user_id = target_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reset_mfa(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reset_mfa(text) TO authenticated;
