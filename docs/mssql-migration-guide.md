# PostgreSQL (Supabase) → Microsoft SQL Server: Migration Guide

This guide is for the engineering team migrating the ADEC Sensor Network Tracker
out of Supabase/PostgreSQL into Microsoft SQL Server. It maps every
PostgreSQL-specific construct in this database to its MS SQL equivalent and flags
the decisions a human needs to make.

Read alongside:
- [`schema/current-schema.sql`](../schema/current-schema.sql): the exact current DDL (with inline `[MSSQL]` tags).
- [`docs/data-dictionary.md`](data-dictionary.md): plain-English meaning of every table/column.

---

## 1. Data-type mapping

| PostgreSQL | Microsoft SQL Server | Notes |
|---|---|---|
| `uuid` | `UNIQUEIDENTIFIER` | |
| `gen_random_uuid()` (default) | `NEWID()` | Use `NEWSEQUENTIALID()` only for clustered-PK perf if needed. |
| `text` | `NVARCHAR(MAX)` | Or sized `NVARCHAR(n)` where a sane limit exists (emails, ids, names). |
| `timestamptz` (timestamp w/ tz) | `DATETIMEOFFSET` | Preserves the timezone offset. |
| `now()` (default) | `SYSDATETIMEOFFSET()` | |
| `boolean` | `BIT` | true/false → 1/0. |
| `jsonb` | `NVARCHAR(MAX)` + `CHECK (ISJSON(col) = 1)` | Query with `JSON_VALUE` / `OPENJSON`. |
| `text[]` (array) | **child table** (recommended) or `NVARCHAR(MAX)` JSON | See §2. |

---

## 2. Array columns (the biggest structural decision)

PostgreSQL stores small lists inline as arrays. MS SQL has no array type. The six
array columns and the recommended handling:

| Column | What it holds | Recommended MS SQL shape |
|---|---|---|
| `sensors.status` | multiple status labels per pod | **child table** `sensor_status(sensor_id, status)`: it's queried/filtered, so normalize it |
| `contacts.communities` | community ids a contact serves | **child table** `contact_communities(contact_id, community_id)`: this is a real many-to-many; a junction table is the correct relational model |
| `collocations.sensor_ids` | pods in a study | **child table** `collocation_sensors(collocation_id, sensor_id)` |
| `service_tickets.sensor_ids` | pods on a ticket | **child table** `service_ticket_sensors(ticket_id, sensor_id)` |
| `notes.merged_sf_ids` | absorbed Salesforce ids (provenance only) | JSON/delimited string is fine: it's never queried, just stored |
| `comms.merged_sf_ids` | same | JSON/delimited string is fine |

**Why child tables for the first four:** the app filters/joins on these values
(e.g. "all pods with an SD Card Issue", "all contacts for Bethel"). A normalized
junction table makes those queries correct and indexable in MS SQL. The last two
are pure provenance metadata, so a string column is acceptable.

When exporting, expand each array into the child-table rows (one row per element).

---

## 3. JSON columns

`audits.analysis_results`, `audits.analysis_chart_data`,
`collocations.analysis_results`, `collocations.analysis_chart_data` are `jsonb`.
Also several `text` columns hold JSON-as-text: `audits.notes`,
`collocations.notes`, `service_tickets.quant_notes` (each is a JSON array of
progress-note objects `{text, by, at, ...}`).

- Store as `NVARCHAR(MAX)` with `CHECK (ISJSON(col) = 1)`.
- The app reads/writes these as whole JSON blobs; you can keep that pattern, or
  normalize the progress-note arrays into a `progress_notes` child table if you
  want them queryable. Normalizing is optional.

---

## 4. Identity / authentication (must re-home)

The app currently uses **Supabase Auth**. The only schema dependency is:

```
profiles.id  →  auth.users(id)   (FK, ON DELETE CASCADE)
```

`profiles` is the app's user table; `auth.users` is Supabase-managed and will not
exist in MS SQL.

- Provide your own identity store (Azure AD / Entra ID, or a SQL users table).
- `profiles.id` becomes the FK to that store (or a standalone PK if identity is
  external).
- `profiles.role` (`user` / `admin`) drives in-app permissions: preserve it.
- The signup allow-list (`allowed_emails` + the `is_email_allowed` rule) gates who
  can get an account. Re-implement that gate in the new auth flow.

---

## 5. Row Level Security (RLS) → MS SQL security

Every table has PostgreSQL RLS policies restricting all access to the
`authenticated` role (a logged-in app user). See `SECURITY.md` and
`supabase/migrations/` for the full policy set. Summary of intent to reproduce:

- **All data** is readable/writable only by authenticated app users (no anonymous
  access).
- **Deletes** of the irreversible records (sensors, communities, contacts, notes,
  comms, tickets, audits, collocations) are **admin-only**.
- **`allowed_emails`** and **`app_settings`** writes are **admin-only**.

In MS SQL, implement this with database roles + `GRANT`/`DENY`, and/or SQL Server
**Row-Level Security** (security policies with predicate functions) if you need
the same row-scoped enforcement. For most of this app, role-based grants
(app_user vs app_admin) on the tables/stored procedures are sufficient, since the
policies here are role-based, not per-row.

---

## 6. Functions, triggers, cron

These PostgreSQL/Supabase server-side pieces exist (see `supabase/migrations/`):

- **RPCs/functions:** `is_email_allowed`, `send_user_invite`, `delete_auth_user`,
  `admin_reset_mfa`, `upsert_profile`, `append_progress_note`. Re-implement the
  ones still needed as MS SQL stored procedures. (`append_progress_note` exists to
  make concurrent progress-note appends race-free: keep that behavior.)
- **Trigger:** `set_updated_by()` stamps `updated_by`/`updated_at` on update for a
  set of tables. MS SQL: an `AFTER UPDATE` trigger or handle in the app/stored proc.
- **Cron:** a scheduled job auto-purges trash older than 30 days
  (`trash_auto_purge_30d`). MS SQL: a SQL Server Agent job.
- The old QuantAQ integration (API/cron/alerts) was **fully removed**, so there's
  nothing to migrate there.

---

## 7. Indexes

Recreate the indexes in `schema/current-schema.sql`. Two PostgreSQL-isms:

- **Partial indexes** (`... WHERE deleted_at IS NOT NULL`, `... WHERE sf_id IS NOT
  NULL`) → MS SQL **filtered indexes** (`CREATE INDEX ... WHERE ...`), supported.
- **GIN index** on `service_tickets.sensor_ids` → not applicable; if `sensor_ids`
  becomes a child table (§2) you index the child table's FK instead.

---

## 8. Referential integrity to verify on import

Most foreign keys are clean and enforced (see the constraints list in
`current-schema.sql`). A few references are **loose text** by design, with no FK:

- `note_tags.tag_id` / `comm_tags.tag_id`: polymorphic (sensor/community/contact
  by `tag_type`). If you split these into typed link tables (§2 pattern), you can
  add real FKs.
- `audits.community_id`, `audits.audit_pod_id`, `audits.community_pod_id`,
  `install_history.sensor_id`, `service_tickets.sensor_id(s)`: loose pod/community
  text refs (audits/tickets can reference imported pods not in `sensors`).

Before/after the data load, run the orphan-tag integrity check (in `SECURITY.md`
and used during handoff prep) to confirm no dangling references: it should be 0.

---

## 9. Suggested migration order

Load tables parents-first so FKs satisfy:

1. `profiles` (after identity is set up)
2. `communities` (self-referencing: load roots first, then children, or defer the
   `parent_id` FK until all rows are in)
3. `sensors`, `contacts`
4. `notes`, `comms`, `audits`, `collocations`, `service_tickets`, `install_history`,
   `community_files`, `community_tags`, `app_settings`, `allowed_emails`
5. The link tables / expanded array child tables last:
   `note_tags`, `comm_tags`, and the new `*_sensors` / `contact_communities` /
   `sensor_status` child tables.

---

## 10a. Event-time timezone convention (IMPORTANT)

`notes.date` and `comms.date` are **event times entered in Alaska local time**.
Because the columns are `timestamptz`, PostgreSQL stores them stamped `+00:00`,
so the *UTC components* of the stored value are actually the intended **Alaska
wall-clock** time (e.g. a stored `2026-06-08T14:30:00+00:00` means **2:30 PM
Alaska**, not 2:30 PM UTC). The app normalizes this on read.

By contrast, the audit/lifecycle timestamps (`created_at`, `updated_at`,
`closed_at`, `deleted_at`, `*_upload_date`) are **true UTC instants** and should
be converted to Alaska time for display normally.

**Recommendation for MS SQL:** during the data load, convert `notes.date` /
`comms.date` to **true `DATETIMEOFFSET` instants in the Alaska offset** (i.e.
re-interpret the stored UTC wall-clock as `America/Anchorage`, accounting for
DST), so going forward all timestamps are real instants and no special-case
display logic is needed. The other timestamp columns load as-is (already true
instants).

## 10b. Dates stored as text

Several date columns are `text` (ISO strings), not real dates:
`sensors.date_purchased/date_installed/collocation_dates`,
`audits.start_date/end_date`, `collocations.start_date/end_date`,
`install_history.installed_date/removed_date`. `collocation_dates` genuinely holds
free-form ranges; the single-value ones could be cast to `DATE` during import if
you want real date typing and validation in MS SQL. Decide per column; the data is
ISO-formatted where populated.
