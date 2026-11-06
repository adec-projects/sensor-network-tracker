-- UNDO for supabase/migrations/20261106170000_require_trusted_session_storage.sql
-- Removes only the file-storage sign-in rule. Takes effect immediately.

DROP POLICY IF EXISTS require_trusted_session_community_files ON storage.objects;

-- Should return zero rows.
SELECT policyname FROM pg_policies
 WHERE schemaname = 'storage' AND tablename = 'objects'
   AND policyname = 'require_trusted_session_community_files';
