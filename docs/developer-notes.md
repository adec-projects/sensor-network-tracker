# Developer notes

File map and conventions for anyone maintaining or reviewing the code. For the
system overview see [`../ARCHITECTURE.md`](../ARCHITECTURE.md); for the database see
[`../schema/current-schema.sql`](../schema/current-schema.sql) and
[`data-dictionary.md`](data-dictionary.md).

## What it is

Internal tool for the Alaska Department of Environmental Conservation to track air
quality sensors (QuantAQ Modulairs), the communities they are deployed in, and the
contacts at each site. It replaced a Salesforce workflow.

Live at: https://adec-projects.github.io/sensor-network-tracker/

## How to run

- **Locally:** open `index.html` in a browser. There is no build step. It is plain
  HTML, CSS, and JavaScript that loads the Supabase library from a CDN and talks
  directly to the hosted Supabase project.
- **Deployed:** GitHub Pages serves `main` at the URL above. Pushing to `main`
  publishes it.

Both modes point at the same Supabase project, so local edits read and write
production data.

## Architecture

Two pieces:

1. **Static frontend** (this repo): served by GitHub Pages, or opened locally.
2. **Supabase:** PostgreSQL database, authentication, storage, and one scheduled job
   (a nightly trash purge via pg_cron). All data lives here.

Data flow: browser to `supabase-client.js` (the `db` helpers) to Supabase. There is
no custom backend server. QuantAQ is the hardware manufacturer; there is no automatic
API integration (it was removed), so sensor issues are logged manually.

## File map

### Active app files
- **`index.html`:** all views, modals, and layout as a single page. Views toggle via
  the `.active` class; modals via `.open`.
- **`styles.css`:** full styling and the design tokens in `:root`.
- **`app.js`:** main application logic (rendering, sensors, communities, contacts,
  notes, comms, files, auth UI).
- **`supabase-client.js`:** Supabase client setup and the `db` helper object. All
  create/read/update/delete, auth, and RPC calls go through here. The key in this file
  is the public anon key; Row Level Security enforces access.

### Database and schema reference
- **`schema/current-schema.sql`:** authoritative current schema (reverse-engineered
  from production), the single source of truth for table structure, with inline SQL
  Server translation notes.
- **`docs/data-dictionary.md`:** plain-English meaning of every table and column.
- **`docs/mssql-migration-guide.md`:** PostgreSQL to Microsoft SQL Server translation
  guide for the State of Alaska handoff.
- **`supabase/config.toml`:** Supabase CLI config.
- **`supabase/migrations/`:** timestamped SQL migrations, applied via `supabase db
  push`. Several later migrations were applied by hand in the SQL editor, so the live
  `schema_migrations` ledger lags the repo. The live schema is current regardless.
- **`archive/legacy-sql/`:** retired one-off setup scripts (seed data, original
  collocations DDL). Historical only; never re-run.

### One-off importer tools
Standalone HTML pages in `archive/` that read a CSV or paste and write to Supabase.
Open directly in a browser when needed; they are not linked from the main app. See
[`importers.md`](importers.md).

### User guide
- `user-guide.html`: the rendered user guide for DEC staff.
- `user-guide-editor.html`: in-browser editor for the guide.

## Key concepts
- **About 40 communities** across Alaska, each typically with one sensor at a gathering
  place (school, tribal office, library). The list lives in the `communities` table,
  not in code.
- **3 regulatory sites** (Anchorage, Fairbanks, Juneau) with permanent pods.
- **Audit pods** travel to communities for roughly one-week collocations to validate
  sensor data.
- **Sensor types:** Community Pod, Permanent Pod, Audit Pod, Not Assigned.
- **Cross-tagging:** notes and comms can be tagged to multiple sensors, communities,
  and contacts via `note_tags` / `comm_tags`, so one record appears in the history of
  everything it is tagged to.
- **Automatic movement notes** are written when a sensor is moved between communities.
- **Community tags** (for example "Regulatory Site", "Interior Network") are
  customizable per community.

## Sensor statuses
Manually applied: Online, Offline, Lost Connection, Lab Storage, Needs Repair, PM
Sensor Issue, Gaseous Sensor Issue, SD Card Issue, Possible Auto Shutoff Firmware
Issue. Workflow-driven: Collocation, Auditing a Community, Service at Quant, Quant
Ticket in Progress.

Status is a list (`text[]`): a sensor can be both "Online" and "PM Sensor Issue" at
once.

## Authentication and access control
- Supabase email and password auth.
- The `allowed_emails` table plus the `is_email_allowed` function gate signups: only
  listed emails can create accounts, enforced by a database trigger, not the browser.
- Row Level Security on every table. The public anon key in `supabase-client.js` is
  safe to commit; it is designed to be public.

## Conventions
- Data access goes through the `db.*` helpers in `supabase-client.js`, not direct
  `supabase.from(...)` calls in `app.js`.
- Views are toggled with the `.active` class; modals use `.open`.
- When changing the schema, add a new file under `supabase/migrations/`; do not edit
  old ones.
- Design: navy blue, gold, and white only; DM Sans for UI and JetBrains Mono for
  sensor IDs. Design tokens live in `:root`.
