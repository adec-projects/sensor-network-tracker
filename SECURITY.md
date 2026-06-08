# Security: Database Access Audit

The whole app is gated by Supabase Row Level Security (RLS). The public anon
key committed in `supabase-client.js` is **safe to be public**: it can't read
or write anything on its own. Every table requires a logged-in, approved user.

How "approved" works: only emails on the `allowed_emails` table can create an
account. That list is managed by admins and enforced by a database trigger
(`is_email_allowed`), not just the browser.

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
```

**What a healthy result looks like:**

- Query **#1 returns no rows** (every table enforces RLS).
- Query **#2 returns no rows** (no table is exposed to the public key).
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
