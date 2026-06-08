# ADEC Sensor Network Tracker — Handoff Index

Entry point and document map for migrating the project off Supabase
(PostgreSQL) to Microsoft SQL Server. Current as of June 2026.

## System
Internal ADEC tool tracking air-quality sensor pods (QuantAQ Modulairs), the
Alaska communities they're deployed in, and site contacts; replaced a Salesforce
workflow. Vanilla HTML/CSS/JS front end against a Supabase/PostgreSQL backend; all
data access is centralized in `supabase-client.js` (the `db` helper). Architecture
overview in [`AGENTS.md`](AGENTS.md).

## Backend documentation
| Document | Contents |
|---|---|
| [`schema/current-schema.sql`](schema/current-schema.sql) | Authoritative current DDL — 16 tables, keys, indexes — reverse-engineered from production, with inline `[MSSQL]` translation notes. Source of truth for structure. (`supabase-schema.sql` is a stale snapshot, marked archived.) |
| [`docs/data-dictionary.md`](docs/data-dictionary.md) | Table/column semantics. |
| [`docs/mssql-migration-guide.md`](docs/mssql-migration-guide.md) | PostgreSQL→MS SQL mapping: types, arrays, JSON, timestamps, RLS, auth, functions. |
| [`docs/mssql-migration-runbook.md`](docs/mssql-migration-runbook.md) | Step-by-step transfer procedure with pre-flight and post-load validation. |
| [`SECURITY.md`](SECURITY.md) | RLS model (authenticated-only, admin-gated deletes) and verification queries. |

## Migration constraints (detail in the guide)
- Auth (Supabase Auth / `auth.users`), RLS policies, DB functions/triggers/cron,
  and file storage are platform-specific and require MS SQL/Azure equivalents.
- Six `text[]` array columns normalize to child tables (guide §2; expansion
  queries in the runbook).
- `notes.date` / `comms.date` are Alaska wall-clock event times in a `timestamptz`
  column — convert to true Alaska-offset instants on load (guide §10a). Other
  timestamps are already true instants.
- Several `text` columns carry JSON or free-form dates (noted per column).

## Repository history / one-off scripts (do not re-run)
- `supabase/migrations/` — forward-only schema change history.
- `archive/legacy-sql/` — retired setup scripts.
- `sf-export/` (git-ignored) — Salesforce import/fix scripts; contain PII, not
  committed, never to be re-run.
