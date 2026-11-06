-- Salesforce provenance for audits, so the Salesforce transfer tool
-- (tools/sf-transfer/) can import audit records idempotently: each Salesforce
-- record becomes at most one audit, and re-running the tool never duplicates.
-- Mirrors the sf_id / merged_sf_ids / logged_by columns notes and comms already
-- have (20260603130000, 20260604000000). Adds columns only; no data changes.
--
-- Safe to run more than once.

ALTER TABLE public.audits ADD COLUMN IF NOT EXISTS sf_id         text;
ALTER TABLE public.audits ADD COLUMN IF NOT EXISTS merged_sf_ids text[] DEFAULT '{}';

CREATE UNIQUE INDEX IF NOT EXISTS uq_audits_sf_id ON public.audits(sf_id) WHERE sf_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
