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

`notes.additional_info` is a **mixed** column: it holds JSON for status-change
and move notes (the structured before/after data), but plain free text (or empty)
for ordinary notes. Do NOT put an unconditional `ISJSON` CHECK on it; leave it
`NVARCHAR(MAX)` and treat it as JSON only where the note type warrants.

- Store the always-JSON columns as `NVARCHAR(MAX)` with `CHECK (ISJSON(col) = 1)`.
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
- **MFA is in use.** The app reads `app_settings.mfa_required` and, when set,
  requires a TOTP challenge after login; admins can reset a user's MFA
  (`admin_reset_mfa`, which clears Supabase `auth.mfa_factors`). The new identity
  provider needs an equivalent MFA enforcement and an admin MFA-reset path. (Note:
  today the MFA gate is enforced in the UI, not in RLS — see SECURITY.md.)

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

These PostgreSQL/Supabase server-side pieces exist (definitions in
`supabase/migrations/`). The behavior to preserve, function by function:

- **`is_email_allowed(email)`** — the signup gate. Case-insensitive email match
  against `allowed_emails`, AND the row must be active (`status='active'` or null).
  Returns boolean. (`20260422221400_hardening_pass.sql`)
- **`upsert_profile(id, email, name)`** — on INSERT it sets the profile's `role`
  from the matching `allowed_emails` row; on conflict it updates only the name and
  **never overwrites an admin-set role**. (`20260421210700_sync_profile_role...`)
- **`sync_my_role()`** — sets the caller's `profiles.role` from their
  `allowed_emails` entry (used by the app to keep RLS role in sync without letting
  a user change their own role). (`20260608030000_fix_profile_role_escalation.sql`)
- **`append_progress_note(kind, id, text, contacts)`** — race-free single-statement
  append of a progress note to a ticket/audit/collocation; stamps the note `at`
  time in **America/Anchorage** wall-clock. Keep both the atomicity and the AK-time.
  (`20260423213800_progress_note_ak_time.sql`)
- **`edit_progress_note(kind, id, at, by, old_text, new_text, contacts)`** and
  **`delete_progress_note(kind, id, at, by, old_text)`** — race-free single-UPDATE
  edit/delete of one progress note inside the same JSON array. They locate the
  target by its `(at, by, text)` identity (not by array index) and rebuild the
  array server-side, so a concurrent append isn't clobbered. The client falls
  back to a full-array rewrite if these aren't present, but reproduce them in
  T-SQL (`OPENJSON` to find the element + `JSON_MODIFY` to rewrite, same approach
  as append) for the same safety. (`20260608040000_edit_delete_progress_note.sql`)
- **`send_user_invite`, `delete_auth_user`, `admin_reset_mfa`** — admin-only user
  management. `delete_auth_user` and `admin_reset_mfa` reach into Supabase's
  `auth.users` / `auth.mfa_factors` schema, so they're tied to Supabase Auth and
  must be re-expressed against the new identity provider.
- **Trigger `set_updated_by()`** — on UPDATE sets `updated_by = auth.uid()` (only
  when there is a logged-in user) and bumps `updated_at = now()` **only for
  `communities`, `contacts`, `notes`, `comms`** (not sensors/tickets/audits/
  collocations). A naive "set updated_at on every table" reimplementation would
  change behavior; match the table list.
- **Cron — `purge_old_trash()`**, scheduled as pg_cron job **`purge-old-trash`**,
  daily at **09:00 UTC**. Hard-deletes rows whose `deleted_at` is older than
  **30 days** from exactly five tables: `notes`, `comms`, `service_tickets`,
  `audits`, `collocations` (NOT sensors). Reproduce as a SQL Server Agent job with
  the same cutoff and tables.
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
