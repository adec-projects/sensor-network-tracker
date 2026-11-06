# Security: Database Access Audit

The whole app is gated by Supabase Row Level Security (RLS). The public anon
key committed in `supabase-client.js` is **safe to be public**: it can't read
or write anything on its own. Every table requires a logged-in, approved user.

How "approved" works: only emails on the `allowed_emails` table can create an
account. That list is managed by admins and enforced by a database trigger
(`is_email_allowed`), not just the browser.

## Sign-in rules enforced by the database (added 2026-11-06)

Being logged in is not enough to see data. Every public table, plus the
`community-files` storage bucket, carries a RESTRICTIVE policy that calls
`public.session_is_trusted()`. RESTRICTIVE means it is checked **in addition to**
the normal policies above. A login is trusted only when all of these hold:

1. its email is **active** in `allowed_emails`, so archived or revoked users are cut off
   even if they still know their password;
2. it has **no pending temporary password** from an admin reset; and
3. it **passed the authenticator step** (`aal2`), or an admin has switched
   "Require MFA" off, or the user has no authenticator yet (first-time setup).

Functions the sign-in screen needs before the code is entered
(`is_email_allowed`, `get_admin_contacts`, `password_change_required`,
`change_my_password`) are SECURITY DEFINER and keep working.

**Emergency undo** (if people are locked out), run in the SQL Editor:
`supabase/rollback/undo_require_trusted_session.sql` (tables) and
`supabase/rollback/undo_require_trusted_session_storage.sql` (files).

## The audit queries

Run these in the **Supabase SQL editor** (Project → SQL Editor) any time you've
changed tables or policies: especially after editing anything by hand in the
dashboard, which is how stray policies have crept in before.

```sql
-- 1. Any public table with RLS turned OFF (wide open: should be ZERO rows)
SELECT tablename AS "RLS DISABLED: DANGER"
FROM pg_tables
WHERE schemaname = 'public'
  AND NOT rowsecurity
ORDER BY tablename;

-- 2. Any policy that lets anon / public (the public key) in: should be ZERO rows
SELECT tablename, policyname, cmd, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND roles && ARRAY['anon','public']::name[]
ORDER BY tablename;

-- 3. Full policy inventory, for your records / spotting duplicates
SELECT tablename, policyname, cmd, roles, qual AS using_clause, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd;

-- 4. Any table MISSING the sign-in rule: should be ZERO rows.
--    (If a new table was added, re-run
--     supabase/migrations/20261106150000_require_trusted_session.sql.)
SELECT c.relname AS "MISSING require_trusted_session"
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND NOT EXISTS (SELECT 1 FROM pg_policies p
                  WHERE p.schemaname = 'public' AND p.tablename = c.relname
                    AND p.policyname = 'require_trusted_session')
ORDER BY 1;
```

**What a healthy result looks like:**

- Query **#1 returns no rows** (every table enforces RLS).
- Query **#2 returns no rows** (no table is exposed to the public key).
- Query **#4 returns no rows** (every table has the sign-in rule).
- Query **#3** shows every `roles` column as `{authenticated}`. Anything showing
  `{anon}` or `{public}`, or a write policy with `using/with_check = true` that
  *should* be admin-gated, is a problem: see below.

## If something looks wrong

- **A table in #1 (RLS off):** turn it on and add authenticated-only policies,
  matching the other tables. Example pattern (replace `your_table`):

  ```sql
  ALTER TABLE public.your_table ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "Authenticated users can read your_table"
      ON public.your_table FOR SELECT TO authenticated USING (true);
  CREATE POLICY "Authenticated users can insert your_table"
      ON public.your_table FOR INSERT TO authenticated WITH CHECK (true);
  CREATE POLICY "Authenticated users can update your_table"
      ON public.your_table FOR UPDATE TO authenticated USING (true);
  CREATE POLICY "Admins can delete your_table"
      ON public.your_table FOR DELETE TO authenticated
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
  NOTIFY pgrst, 'reload schema';
  ```

- **A stray permissive policy** (a short cryptic name like `p31`/`p32` with
  `using`/`with_check = true` sitting next to a stricter admin policy): drop it
  by name. Postgres OR's policies together, so one `true` policy defeats the
  strict one beside it.

  ```sql
  DROP POLICY IF EXISTS "p31" ON public.allowed_emails;
  ```

Always capture the fix as a new file in `supabase/migrations/` so it can't drift
back and a fresh database stands up secured. Never edit old migrations.

## Audit history

- **2026-06-05**: Full audit. All 16 tables RLS-enabled and authenticated-only.
  Found and dropped two stray permissive policies on `allowed_emails` (`p31`
  INSERT `with_check=true`, `p32` DELETE `using=true`) that let any logged-in
  user add or remove authorized users. Locked back to admins only. See
  `supabase/migrations/20260605020000_drop_stray_allowed_emails_policies.sql`.
- **2026-11-06**: Password and MFA overhaul. Found that MFA and "archived user"
  were enforced only in the browser, so a password alone, or an archived user's
  password, could read data via the API. Also found that Settings > Change
  Password never checked the current password. Fixed both: the database now
  enforces sign-in rules on all 16 tables and the `community-files` bucket
  (migrations `20261106140000` to `20261106170000`), and password changes
  are checked server-side (`20261106120000`). Added admin-assisted password
  reset with forced change (`20261106160000`). Verified live: password-only
  logins and strangers get no rows or files; full sign-ins work normally.
  Follow-up the same day: the sub-query form of the new rule tripped Postgres's
  "infinite recursion" guard on `profiles`, whose UPDATE policies look up
  `profiles` themselves. Admin role changes failed as a result. On `profiles`
  only, the rule now calls the function directly (`20261106190000`). **If you
  add a policy that looks up its own table, use the direct-call form on that
  table too.** The admin contact list now also excludes admins who haven't
  created an account (`20261106180000`).
