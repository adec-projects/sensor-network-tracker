-- STAGE C: apply the same sign-in rule to uploaded files (Storage bucket
-- "community-files").
--
-- Stage B protected every table. Uploaded files live in Supabase Storage
-- (storage.objects), which has its own rules, so this adds one RESTRICTIVE
-- policy there too: signed-in users can list, open, upload, or delete files in
-- community-files only when session_is_trusted() is true. Other buckets (none
-- today) are untouched. Existing storage policies keep working on top.
--
-- UNDO: run supabase/rollback/undo_require_trusted_session_storage.sql
-- Safe to run more than once.

DROP POLICY IF EXISTS require_trusted_session_community_files ON storage.objects;

CREATE POLICY require_trusted_session_community_files
    ON storage.objects
    AS RESTRICTIVE
    FOR ALL
    TO authenticated
    USING      (bucket_id <> 'community-files' OR (SELECT public.session_is_trusted()))
    WITH CHECK (bucket_id <> 'community-files' OR (SELECT public.session_is_trusted()));

-- Show the result: should list the new policy as RESTRICTIVE.
SELECT policyname, permissive, cmd, roles
  FROM pg_policies
 WHERE schemaname = 'storage' AND tablename = 'objects'
 ORDER BY policyname;
