-- Salesforce audit import: provenance tag + relax pod-id constraints.
-- Historical audits imported from the audit-records ZIP are tagged
-- source='salesforce_import' and may lack a travelling/community pod id.

ALTER TABLE audits ADD COLUMN IF NOT EXISTS source text DEFAULT 'manual';

ALTER TABLE audits ALTER COLUMN audit_pod_id     DROP NOT NULL;
ALTER TABLE audits ALTER COLUMN community_pod_id DROP NOT NULL;

-- The original audit Excel is uploaded to the community-files bucket and
-- linked here, so the source workbook travels with the audit record.
ALTER TABLE audits ADD COLUMN IF NOT EXISTS analysis_file_path text DEFAULT '';
ALTER TABLE audits ADD COLUMN IF NOT EXISTS analysis_file_name text DEFAULT '';
