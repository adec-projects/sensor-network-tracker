# ADEC Sensor Network Tracker

Internal tool for the Alaska Department of Environmental Conservation (ADEC) to track air quality sensors (QuantAQ Modulairs), the Alaska communities they're deployed in, and the contacts at each site.

**Live app:** https://adec-projects.github.io/sensor-network-tracker/

## What's in this repo

- A vanilla HTML/CSS/JS frontend (`index.html`, `styles.css`, `app.js`) with no build step.
- A Supabase project under `supabase/` holding the Postgres database and its migrations.
- A few one-off HTML importer tools (in `archive/`) used to bring data in from Salesforce and spreadsheets during setup.
- An end-user guide (`user-guide.html`).

## Running it

**Locally:**
```
open index.html
```
That's all it takes. The page loads the Supabase JS library from a CDN and talks to the hosted Supabase project directly. You'll be prompted to sign in with an allowed `@alaska.gov` email.

**Local mode reads and writes production data.** There is no separate dev database, so be deliberate about what you click.

**Deployed:** GitHub Pages serves `main` automatically. Push to `main` to ship.

## Docs

| Doc | For |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Project overview, file map, and conventions for developers and AI agents (`CLAUDE.md` just points here). |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How the frontend and Supabase backend fit together. |
| [`HANDOFF.md`](HANDOFF.md) | Index for the Microsoft SQL Server migration handoff. |
| [`schema/current-schema.sql`](schema/current-schema.sql) | Authoritative current database schema. |
| [`docs/data-dictionary.md`](docs/data-dictionary.md) | What every table and column means. |
| [`docs/mssql-migration-guide.md`](docs/mssql-migration-guide.md) | Postgres to MS SQL type/feature mapping. |
| [`docs/mssql-migration-runbook.md`](docs/mssql-migration-runbook.md) | Step-by-step data transfer procedure. |
| [`SECURITY.md`](SECURITY.md) | Access-control model and audit queries. |
| [`docs/importers.md`](docs/importers.md) | The one-off importer pages in `archive/` and when each was used. |
| [`user-guide.html`](user-guide.html) | End-user guide shipped to ADEC staff. |

## Stack

- **Frontend:** plain HTML/CSS/JS, served from GitHub Pages.
- **Backend:** Supabase (Postgres, Auth, Storage).

Sensor issues are noticed and logged manually. There is no longer any automatic QuantAQ API integration (it was removed); QuantAQ is just the hardware manufacturer.

## Access

Sign-ups are gated by an `allowed_emails` table in the database. To add a user, insert their email there, and they can create an account through the normal sign-up flow.
