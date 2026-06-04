-- When duplicate Salesforce activities are merged into one app record, the
-- absorbed siblings' Salesforce IDs are stored here so the importer can treat
-- them as already-imported on future sessions (and not resurface them).

ALTER TABLE comms ADD COLUMN IF NOT EXISTS merged_sf_ids text[] DEFAULT '{}';
ALTER TABLE notes ADD COLUMN IF NOT EXISTS merged_sf_ids text[] DEFAULT '{}';
