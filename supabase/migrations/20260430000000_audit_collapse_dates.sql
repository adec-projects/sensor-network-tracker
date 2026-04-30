-- Collapse the four audit date columns (scheduled_start, scheduled_end,
-- actual_start, actual_end) down to two: start_date and end_date.
--
-- Rationale: in practice the "scheduled vs actual" split caused more
-- confusion than it solved. There is just one start and one end per audit.
-- If the dates slip, you edit them. The single field is the source of
-- truth that every display, report, and history note reads from.
--
-- Migration order matters:
--   1. Add new columns.
--   2. Backfill: prefer the actual_* value if set, otherwise use scheduled_*.
--      This matches what the audit report previously showed
--      (`audit.actualStart || audit.scheduledStart`) so existing reports
--      keep showing the same dates after the rename.
--   3. Drop the four legacy columns.
--   4. Reindex on the new column.
--
-- This is reversible only by restoring from backup — make sure prod is
-- backed up before pushing.
ALTER TABLE audits
    ADD COLUMN IF NOT EXISTS start_date text,
    ADD COLUMN IF NOT EXISTS end_date text;

UPDATE audits
SET start_date = COALESCE(actual_start, scheduled_start),
    end_date   = COALESCE(actual_end,   scheduled_end);

DROP INDEX IF EXISTS idx_audits_status;
ALTER TABLE audits
    DROP COLUMN IF EXISTS scheduled_start,
    DROP COLUMN IF EXISTS scheduled_end,
    DROP COLUMN IF EXISTS actual_start,
    DROP COLUMN IF EXISTS actual_end;

CREATE INDEX IF NOT EXISTS idx_audits_status ON audits(status);
CREATE INDEX IF NOT EXISTS idx_audits_start_date ON audits(start_date);
