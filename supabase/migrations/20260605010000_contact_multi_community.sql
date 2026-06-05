-- Let a contact belong to multiple communities (e.g. one person covering all
-- three Anchorage School District sites). We keep `community_id` as the
-- PRIMARY community (for default display/grouping) and add a `communities`
-- array holding the full membership set (always includes the primary).

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS communities text[] NOT NULL DEFAULT '{}';

-- Backfill: existing single-community contacts get a one-element array.
UPDATE public.contacts
  SET communities = ARRAY[community_id]
  WHERE community_id IS NOT NULL
    AND (communities IS NULL OR communities = '{}');

NOTIFY pgrst, 'reload schema';
