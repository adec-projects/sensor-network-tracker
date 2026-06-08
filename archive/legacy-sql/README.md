# Legacy / one-off SQL — DO NOT RE-RUN

These scripts were used during the initial setup of the project and are kept for
historical reference only. **They are not safe to run against the live database.**

- `seed-data.sql`, `seed-data-clean.sql` — initial sample/seed data inserts.
  Re-running would duplicate or clobber real production data.
- `collocation-schema.sql` — the original `CREATE TABLE collocations` script.
  This DDL is now captured authoritatively in
  [`schema/current-schema.sql`](../../schema/current-schema.sql); this copy is
  historical only.

The single source of truth for the database structure is
[`schema/current-schema.sql`](../../schema/current-schema.sql). For schema
changes over time, see `supabase/migrations/`.

> Note: the original Salesforce-import and data-fix scripts live under the
> git-ignored `sf-export/` directory (they contain PII and are intentionally not
> committed). Those are also one-off and must never be re-run.
