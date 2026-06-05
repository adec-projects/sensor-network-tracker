-- Security audit follow-up: drop two stray permissive policies on
-- allowed_emails that had been created out-of-band (Supabase dashboard),
-- in the same family as the p9/p13/... policies cleaned up in
-- 20260422223300_drop_leftover_open_delete_policies.sql.
--
-- allowed_emails is the table that gates who may have an account, so a
-- permissive policy here is the worst place for one:
--
--   p31  INSERT  WITH CHECK (true)  -> any authenticated user could add
--                                      anyone to the allowed-users list
--                                      (self-invite a friend).
--   p32  DELETE  USING (true)       -> any authenticated user could remove
--                                      entries from the allowed-users list.
--
-- Postgres OR's policies per command, so each of these defeated the
-- admin-only "Admins can insert/delete allowed_emails" policy beside it.
-- Dropping them leaves: p1 (SELECT, all authenticated) + the three
-- admin-gated write policies, so only admins can change who is authorized.
--
-- Verified before writing via:
--   SELECT policyname, cmd, roles, qual, with_check FROM pg_policies
--   WHERE schemaname='public' AND tablename='allowed_emails';

DROP POLICY IF EXISTS "p31" ON public.allowed_emails;
DROP POLICY IF EXISTS "p32" ON public.allowed_emails;
