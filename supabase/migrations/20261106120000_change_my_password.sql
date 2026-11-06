-- Password change without an authenticator code.
--
-- Why this exists: Supabase refuses a password change from an account that has
-- MFA set up unless the session already passed the 6-digit code. That forced
-- people to have their authenticator handy just to change a password they
-- already know. This function instead proves identity the classic way, by
-- checking the CURRENT password, then sets the new one.
--
-- It also closes a gap: the old Settings form asked for the current password
-- but never checked it.
--
-- Safe to run more than once (CREATE OR REPLACE / IF NOT EXISTS).

-- pgcrypto provides crypt()/gen_salt() (bcrypt), the same hashing Supabase Auth
-- uses. Supabase installs it in the "extensions" schema by default; this is a
-- no-op if it is already there.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


-- assert_password_strength: the single source of truth for password rules.
-- Mirrors the browser check (passwordProblem() in app.js) so the rules can't be
-- skipped by calling the database directly.
CREATE OR REPLACE FUNCTION public.assert_password_strength(pw text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
    IF pw IS NULL OR length(pw) < 8 THEN
        RAISE EXCEPTION 'Password must be at least 8 characters.';
    END IF;
    IF length(pw) > 72 THEN
        -- bcrypt only uses the first 72 bytes; refuse rather than silently truncate.
        RAISE EXCEPTION 'Password must be 72 characters or fewer.';
    END IF;
    IF pw !~ '[A-Za-z]' THEN
        RAISE EXCEPTION 'Password must include at least one letter.';
    END IF;
    IF pw !~ '[0-9]' THEN
        RAISE EXCEPTION 'Password must include at least one number.';
    END IF;
    IF pw !~ '[^A-Za-z0-9]' THEN
        RAISE EXCEPTION 'Password must include at least one symbol (e.g. !@#$%%).';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assert_password_strength(text) TO anon, authenticated;


-- change_my_password: signed-in user changes their own password.
-- Requires the correct current password. No authenticator code needed.
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
           updated_at = now()
     WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.change_my_password(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_my_password(text, text) TO authenticated;
