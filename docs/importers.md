# Importer tools

This repo contains several standalone HTML pages used to load data into Supabase during initial setup and one-off data cleanups. They are **not linked from the main app** — open them directly in a browser when you need them.

Each importer is a self-contained page that loads the Supabase JS library from a CDN, authenticates against the same project as the main app, and writes to one or more tables. They're deliberately kept as plain HTML so they survive framework changes and can be used even after the main app evolves.

**⚠️ All importers write to production Supabase.** There is no dev database. Open them only when you intend to run them.

## Available importers

### `audit-importer.html`
Imports historical audit Excel sheets (the "Audit Sheets" ZIP) into real `audits` rows.
Per file it parses the filename metadata, locates the pre-computed DQI table in whichever
sheet holds it (`Sheet1` / `RESULTS` / `Hour Data` / `Graphs`), and shows a **preview card**
for each audit — editable community/pods/dates plus the pulled DQI table. **Nothing is written
until you Approve that card.** On approve it uploads the source `.xls` to the `community-files`
bucket and creates the audit (tagged `source='salesforce_import'`, with the Excel linked via
`analysis_file_path`). Already-on-app audits (same community + date) are flagged and skipped.
Chart data is left null on purpose so the audit shows the **report's** DQI numbers, not a
recomputed version (the app excludes the first 24h; the reports don't). Requires the
`20260603120000_sf_audit_provenance.sql` migration first.

**Use when:** loading the historical Salesforce audit sheets. See `docs/sf-integration-plan.md`.

### `sf-importer.html`
Track B of the Salesforce migration: imports the classified comms + notes (from the full
Data Export) community-by-community. Load `sf-export/sf-import-data.json` (produced by the
preprocessor), pick a community, and review each communication / device-history note —
editable type, date, community, contact, sensor tag — then Approve / Skip (or "Approve all
pending here"). Writes to `comms`/`notes` with `comm_tags`/`note_tags`, tagged
`source='salesforce_import'` + `sf_id` (skips already-imported records). A Reset button
removes all SF-imported comms/notes. Requires the `20260603130000_sf_comms_notes_provenance.sql`
migration. Bulk `List Email:` blasts and audit entries are excluded by the preprocessor.

**Use when:** importing the Salesforce activity history. See `docs/sf-integration-plan.md`.

### `sf-contact-migrator.html`
Migrates contacts out of the legacy Salesforce system into the `contacts` table. Handles the column-name mapping, de-dupes by email, and assigns contacts to communities.

**Use when:** bootstrapping contacts from a fresh Salesforce export.

### `sensor-data-importer.html`
Loads SOA tag IDs and purchase dates onto existing `sensors` rows. Expects a CSV paste or upload with sensor ID, SOA tag, and purchase date columns.

**Use when:** you have a new batch of sensors from procurement and need to fill in their asset-tracking fields.

### `sensor-location-importer.html`
Imports sensor location strings and collocation history. Touches `sensors.location`, `sensors.collocation_dates`, and (if present) any related collocation tables. Useful for backfilling physical location details after initial deployment.

**Use when:** sensor locations were tracked in a spreadsheet separately and need to be reconciled into the database.

### `install-date-importer.html`
Imports sensor install dates. Writes install-date fields onto `sensors` rows matched by ID.

**Use when:** backfilling install dates from a spreadsheet or paper records.

## When to add a new importer

If you're about to do a one-off data migration, consider whether it's a one-time paste into the Supabase SQL editor (simpler) or a reusable importer (appropriate when non-developers will run it, or when the migration needs client-side parsing).

When adding a new importer:
- Copy the scaffold from an existing one — they share the same Supabase bootstrap and design.
- Require sign-in. RLS will block writes anyway, but an early auth check gives a better error.
- Dry-run mode first: show what *would* be changed before committing the transaction.
- Log to a visible status area on the page, not just `console.log`.
- Add a short entry to this file.

## Retiring importers

Importers from completed migrations (e.g., Salesforce → Supabase) can stay in the repo indefinitely — they're small, self-contained, and serve as documentation of the original data shape. Only remove one if it's actively broken or references a table that no longer exists.
