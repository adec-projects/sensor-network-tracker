-- Admin-assisted password reset (no email needed).
--
-- Flow: an admin sets a TEMPORARY password for someone who forgot theirs and
-- tells them by phone/Teams. That person signs in with it (plus their
-- authenticator code, as usual) and must choose a new password before they can
-- see any data. Nothing leaves the app: no email sender, no reset links.
--
-- The "must change" state lives in auth.users.raw_app_meta_data, which users
-- cannot edit themselves (only SECURITY DEFINER functions like these can).
--
-- This file:
--   1. admin_set_temp_password(target_email, temp_password)  (new)
--   2. password_change_required()                            (new)
--   3. change_my_password(...)    (updated: also clears the "must change" flag)
--   4. session_is_trusted()       (updated: blocks data until the temp password
--                                  is replaced)
--
-- Safe to run more than once. Users without the flag (everyone today) are
-- unaffected by 3 and 4.


-- 1. Admin sets a temporary password for another user.
CREATE OR REPLACE FUNCTION public.admin_set_temp_password(target_email text, temp_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
    target_id uuid;
    caller_email text;
BEGIN
    -- Caller must be an admin who is fully signed in (password + code).
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
       OR NOT public.session_is_trusted() THEN
        RAISE EXCEPTION 'Only a signed-in administrator can reset passwords.';
    END IF;

    SELECT email INTO caller_email FROM auth.users WHERE id = auth.uid();
    IF lower(target_email) = lower(caller_email) THEN
        RAISE EXCEPTION 'To change your own password, use Settings > Change Password.';
    END IF;

    SELECT id INTO target_id FROM auth.users WHERE lower(email) = lower(target_email);
    IF target_id IS NULL THEN
        RAISE EXCEPTION 'That person has not created an account yet, so there is no password to reset.';
    END IF;

    PERFORM public.assert_password_strength(temp_password);

    UPDATE auth.users
       SET encrypted_password = extensions.crypt(temp_password, extensions.gen_salt('bf', 10)),
           raw_app_meta_data  = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(
                                    'must_change_password', true,
                                    'password_reset_by',    caller_email,
                                    'password_reset_at',    now()),
           updated_at = now()
     WHERE id = target_id;

    -- Sign the person out everywhere so an old session can't linger.
    DELETE FROM auth.sessions WHERE user_id = target_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_temp_password(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_temp_password(text, text) TO authenticated;


-- 2. Does the signed-in user still need to replace a temporary password?
CREATE OR REPLACE FUNCTION public.password_change_required()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT coalesce((SELECT (u.raw_app_meta_data ->> 'must_change_password')::boolean
                       FROM auth.users u WHERE u.id = auth.uid()), false);
$$;

REVOKE ALL ON FUNCTION public.password_change_required() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.password_change_required() TO authenticated;


-- 3. change_my_password: same as before, plus clears the "must change" flag.
CREATE OR REPLACE FUNCTION public.change_my_password(current_password text, new_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
    uid    uuid := auth.uid();
    stored text;
BEGIN
    IF uid IS NULL THEN
        RAISE EXCEPTION 'You must be signed in to change your password.';
    END IF;

    SELECT encrypted_password INTO stored FROM auth.users WHERE id = uid;
    IF stored IS NULL OR stored = ''
       OR stored <> extensions.crypt(coalesce(current_password, ''), stored) THEN
        RAISE EXCEPTION 'Current password is incorrect.';
    END IF;

    IF current_password = new_password THEN
        RAISE EXCEPTION 'New password must be different from your current password.';
    END IF;

    PERFORM public.assert_password_strength(new_password);

    UPDATE auth.users
       SET encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf', 10)),
           raw_app_meta_data  = coalesce(raw_app_meta_data, '{}'::jsonb) - 'must_change_password',
           updated_at = now()
     WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.change_my_password(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_my_password(text, text) TO authenticated;


-- 4. session_is_trusted: same rules as before, plus "no pending temp password".
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
        AND NOT coalesce((SELECT (u.raw_app_meta_data ->> 'must_change_password')::boolean
                            FROM auth.users u WHERE u.id = auth.uid()), false)
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
