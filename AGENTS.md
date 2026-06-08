# ADEC Sensor Network Tracker

## What This Is
Internal tool for Alaska Department of Environmental Conservation (ADEC) to track air quality sensors (QuantAQ Modulairs), the communities they're deployed in, and contacts at each site. Replaces a clunky Salesforce workflow.

Live at: https://adec-projects.github.io/sensor-network-tracker/

## How to Run
- **Locally:** open `index.html` in a browser. There is no build step: it's vanilla HTML + CSS + JS that loads the Supabase JS library from a CDN and talks directly to the hosted Supabase project.
- **Deployed:** GitHub Pages serves `main` at the URL above. Pushing to `main` ships it.

Both modes point at the same Supabase project, so local edits read/write production data. Be deliberate.

## Architecture (current)
Two-piece stack:
1. **Static frontend** (this repo): served by GitHub Pages or opened locally.
2. **Supabase**: Postgres database, auth, storage, and one scheduled job (a nightly trash purge via pg_cron). All data lives here.

QuantAQ is the pod manufacturer (the hardware is QuantAQ Modulairs), but there is no automatic API integration anymore; it was removed, and sensor issues are noticed and logged manually.

Data flow: browser → `supabase-client.js` (`db` helpers) → Supabase. The app has no custom backend server.

See `ARCHITECTURE.md` for the data-flow diagram, `docs/data-dictionary.md` for table-by-table details, and `schema/current-schema.sql` for the exact DDL.

## File Map

### Active app files
- **`index.html`** (~1300 lines): all views, modals, and layout as a single page. Views toggle via `.active` class; modals via `.open`.
- **`styles.css`**: full styling, "Arctic Observatory" theme, design tokens in `:root`.
- **`app.js`** (~11k lines): main app logic: rendering, sensors, communities, contacts, notes, comms, files, auth UI.
- **`supabase-client.js`**: Supabase JS client setup and the `db` helper object (all CRUD, auth, RPC calls go through here). Keys are the public anon key: RLS enforces security.

### Supabase project / schema reference
- **`schema/current-schema.sql`**: ⭐ AUTHORITATIVE current schema (reverse-engineered from live prod; the single source of truth for table structure, with inline MS SQL translation notes).
- **`docs/data-dictionary.md`**: plain-English meaning of every table and column.
- **`docs/mssql-migration-guide.md`**: Postgres→Microsoft SQL Server translation guide (for the State of Alaska handoff).
- **`supabase/config.toml`**: local Supabase CLI config.
- **`supabase/migrations/`**: SQL migrations, timestamped. Run via `supabase db push`. (Note: several later migrations were applied by hand in the SQL editor, so the live `schema_migrations` ledger lags the repo: the live schema is current regardless.)
- **`supabase-schema.sql`**: ⚠️ ARCHIVED/STALE April-2026 dump. Do not use as the schema reference; see `schema/current-schema.sql`.
- **`archive/legacy-sql/`**: retired one-off setup scripts (seed data, original collocations DDL). Historical only: never re-run.

### One-off importer tools (standalone HTML pages)
Each is a self-contained page that reads a CSV/paste and writes to Supabase. Open them directly in a browser when needed; they are not linked from the main app. See `docs/importers.md`.
- `sf-contact-migrator.html`: Salesforce → `contacts` table
- `sensor-data-importer.html`: sensor SOA tags + purchase dates
- `sensor-location-importer.html`: sensor locations + collocation history
- `install-date-importer.html`: sensor install dates

### User guide (end-user docs, not agent docs)
- `user-guide.html`: the rendered user guide shipped to ADEC staff.
- `user-guide-editor.html`: in-browser editor for the guide.

## Key Concepts
- **~40 communities** across Alaska, each typically has 1 sensor at a gathering place (school, tribal office, library). Communities list lives in the `communities` table, not hardcoded.
- **3 regulatory sites** (Anchorage, Fairbanks, Juneau) with permanent pods.
- **Audit pods** travel to communities for ~1 week collocations to validate sensor data.
- **Sensor types**: Community Pod, Permanent Pod, Audit Pod, Not Assigned.
- **Cross-tagging**: notes and comms can be tagged to multiple sensors, communities, and contacts via `note_tags` / `comm_tags`: a single record appears in the history of everything it's tagged to.
- **Auto-generated movement notes** when a sensor is moved between communities.
- **Community tags** (e.g. "Regulatory Site", "Interior Network") are customizable per community.

## Sensor Statuses
Manually applied: Online, Offline, Lost Connection, Lab Storage, Needs Repair, PM Sensor Issue, Gaseous Sensor Issue, SD Card Issue, Possible Auto Shutoff Firmware Issue. Workflow-driven: Collocation, Auditing a Community, Service at Quant, Quant Ticket in Progress.

Status is a `text[]` array: a sensor can be simultaneously "Online" and "PM Sensor Issue".

## Auth & Access Control
- Supabase email+password auth.
- `allowed_emails` table + `is_email_allowed` RPC gates signups: only listed emails can create accounts. Enforced by database trigger, not the browser.
- RLS on every table. The public anon key in `supabase-client.js` is safe to commit: it's designed to be public.

## Design Rules
- **Colors:** navy blue, gold, white only. No teal.
- **Fonts:** DM Sans (UI) + JetBrains Mono (sensor IDs, code).
- Keep the UI simple and beginner-friendly.
- CSS uses custom properties (design tokens) in `:root`.

## Things to Know
- The user is Ayla (ADEC, new-ish to web dev): prefer plain-language explanations and direct action over repeated confirmation.
- `persist()` from the localStorage era is gone; writes go through `db.*` helpers in `supabase-client.js`.
- Views are toggled by adding/removing the `.active` class; modals use `.open`.
- When changing schema, add a new file under `supabase/migrations/`: don't edit old ones.
