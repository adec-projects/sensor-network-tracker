# ADEC Sensor Network Tracker

Internal tool for the Alaska Department of Environmental Conservation (DEC) to track
air quality sensors (QuantAQ Modulairs), the Alaska communities they are deployed in,
and the contacts at each site. It replaced a Salesforce-based workflow.

**Live app:** https://adec-projects.github.io/sensor-network-tracker/

---

## For OIT (technical handoff): start here

This project is being transitioned to DEC for migration into a State-managed database.
The documents below, in order, are the fastest way to understand what you are
inheriting:

1. **[`TRANSITION.md`](TRANSITION.md)** - ownership, access, and the handoff plan. Read
   this first. It explains what accounts the system runs on and what needs to transfer.
2. **[`HANDOFF.md`](HANDOFF.md)** - index to the database migration documents (the plan
   for moving the data into Microsoft SQL Server).
3. **[`schema/current-schema.sql`](schema/current-schema.sql)** - the exact database
   structure (16 tables), with inline notes on translating each piece to SQL Server.
4. **[`docs/data-dictionary.md`](docs/data-dictionary.md)** - the plain-English meaning
   of every table and column.

A complete data export can be produced with [`scripts/backup-database.sh`](scripts/backup-database.sh).

---

## What it is

Two pieces, with no custom server to maintain:

- **Frontend:** plain HTML, CSS, and JavaScript with no build step, served by GitHub
  Pages. The files are `index.html`, `styles.css`, and `app.js`.
- **Backend:** a Supabase project providing the PostgreSQL database, user
  authentication, and file storage. All data access goes through `supabase-client.js`.

There is no automatic sensor/QuantAQ integration; sensor issues are logged manually.
QuantAQ is the hardware manufacturer only.

## Running it

- **Locally:** open `index.html` in a browser. It loads the Supabase JavaScript library
  from a CDN and talks directly to the hosted Supabase project. You sign in with an
  approved `@alaska.gov` email.
- **Deployed:** GitHub Pages serves the `main` branch at the URL above. Pushing to
  `main` publishes it.

Both modes read and write the same production database. To test something risky,
make a throwaway copy first with `scripts/make-test-copy.sh` (copies the live data into
a separate, empty Supabase project).

## Repository layout

```
index.html              The single-page app: all views and modals
app.js                  Application logic (rendering, sensors, communities, notes, etc.)
styles.css              Styling and design tokens
supabase-client.js      The data layer: all database, auth, and storage calls
favicon.svg
user-guide.html         End-user guide shipped to DEC staff
user-guide-editor.html  In-browser editor for that guide

schema/
  current-schema.sql    Authoritative database structure (source of truth)

docs/
  data-dictionary.md        Meaning of every table and column
  mssql-migration-guide.md  PostgreSQL to SQL Server translation
  mssql-migration-runbook.md  Step-by-step data transfer and verification
  importers.md              The one-off data-import tools in archive/
  developer-notes.md        File map and conventions for maintaining the code

supabase/
  config.toml           Supabase CLI project config
  migrations/           Database change history (timestamped SQL)
  rollback/             Undo scripts for the sign-in security rules (emergency use)

scripts/
  backup-database.sh    One-command export of the full database for handoff
  make-test-copy.sh     Copies the live database into an empty test project

tools/sf-transfer/      Salesforce Transfer page (open index.html in a browser; nothing to install)
  index.html            The page: sign in, choose the Salesforce ZIP, review, approve
  sf-transfer-core.js   Reads the export and builds the review cards
  README.md             How to use it

archive/                Retired one-off import tools and setup SQL (historical only)

.github/workflows/
  keepalive.yml         Pings the database every 2 days so the free-tier project does
                        not auto-pause. Temporary: only needed until the data is
                        migrated off Supabase, then it can be deleted.
```

## Documentation index

| Document | Purpose |
|---|---|
| [`TRANSITION.md`](TRANSITION.md) | Ownership, access, and the handoff plan |
| [`HANDOFF.md`](HANDOFF.md) | Index to the database migration documents |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How the frontend and backend fit together |
| [`SECURITY.md`](SECURITY.md) | The access-control model and audit queries |
| [`schema/current-schema.sql`](schema/current-schema.sql) | Exact database structure |
| [`docs/data-dictionary.md`](docs/data-dictionary.md) | What every table and column means |
| [`docs/mssql-migration-guide.md`](docs/mssql-migration-guide.md) | PostgreSQL to SQL Server mapping |
| [`docs/mssql-migration-runbook.md`](docs/mssql-migration-runbook.md) | Step-by-step data transfer |
| [`tools/sf-transfer/README.md`](tools/sf-transfer/README.md) | Salesforce Transfer page: bring new Salesforce records into the app (in the browser) |
| [`docs/importers.md`](docs/importers.md) | The one-off import tools in `archive/` |
| [`docs/developer-notes.md`](docs/developer-notes.md) | File map and conventions for the code |
| [`user-guide.html`](user-guide.html) | End-user guide for DEC staff |
| [`scripts/`](scripts/) | `backup-database.sh` (full backup), `make-test-copy.sh` (test copy of the app) |
| [`supabase/rollback/`](supabase/rollback/) | Emergency undo for the sign-in security rules |

## Access

Sign-ups are gated by an `allowed_emails` table in the database and enforced by a
database trigger. Only listed emails can create an account. See `SECURITY.md` for the
full access-control model and `TRANSITION.md` for who currently controls the accounts.
