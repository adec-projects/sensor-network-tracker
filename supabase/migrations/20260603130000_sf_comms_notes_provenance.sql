-- Salesforce Track B import (comms / notes / files): provenance fields.
-- source marks imported rows (reversible + filterable); sf_id ties each row
-- back to its Salesforce record (traceable + safe to re-run); logged_by holds
-- the original Salesforce author (those people aren't app users).

ALTER TABLE comms ADD COLUMN IF NOT EXISTS source    text DEFAULT 'manual';
ALTER TABLE comms ADD COLUMN IF NOT EXISTS sf_id     text;
ALTER TABLE comms ADD COLUMN IF NOT EXISTS logged_by text DEFAULT '';

ALTER TABLE notes ADD COLUMN IF NOT EXISTS source    text DEFAULT 'manual';
ALTER TABLE notes ADD COLUMN IF NOT EXISTS sf_id     text;
ALTER TABLE notes ADD COLUMN IF NOT EXISTS logged_by text DEFAULT '';

ALTER TABLE community_files ADD COLUMN IF NOT EXISTS source text DEFAULT 'manual';
ALTER TABLE community_files ADD COLUMN IF NOT EXISTS sf_id  text;

-- Idempotency: each Salesforce record imports at most once per table.
CREATE UNIQUE INDEX IF NOT EXISTS uq_comms_sf_id ON comms(sf_id) WHERE sf_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_notes_sf_id ON notes(sf_id) WHERE sf_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_files_sf_id ON community_files(sf_id) WHERE sf_id IS NOT NULL;

-- Let the importer's Reset undo a batch — scoped to imported rows only, so it
-- can't delete normal comms/notes. (comm_tags/note_tags cascade on delete.)
CREATE POLICY "Delete SF-imported comms" ON comms FOR DELETE TO authenticated USING (source = 'salesforce_import');
CREATE POLICY "Delete SF-imported notes" ON notes FOR DELETE TO authenticated USING (source = 'salesforce_import');
