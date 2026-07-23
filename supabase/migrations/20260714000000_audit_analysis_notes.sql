-- Persist the audit "Analysis Note" — the explanation a user types when they
-- click "Proceed Anyway" on a data-quality warning (missing parameter / short
-- collocation). It was already shown in the audit detail view and the generated
-- report, but there was no column to store it, so it was lost on refresh.
--
-- Plain nullable text, defaulting to '' to match how the app reads it.

ALTER TABLE public.audits
    ADD COLUMN IF NOT EXISTS analysis_notes text NOT NULL DEFAULT '';

-- Tell PostgREST to pick up the new column immediately.
NOTIFY pgrst, 'reload schema';
