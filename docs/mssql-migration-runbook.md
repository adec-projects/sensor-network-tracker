# Migration Runbook — Supabase (PostgreSQL) → Microsoft SQL Server

A step-by-step procedure for the State of Alaska team to move the ADEC Sensor
Network Tracker's data and structure into Microsoft SQL Server. Read the
companion docs first:
- [`schema/current-schema.sql`](../schema/current-schema.sql) — the source schema (with `[MSSQL]` tags).
- [`docs/mssql-migration-guide.md`](mssql-migration-guide.md) — type mappings & design decisions.
- [`docs/data-dictionary.md`](data-dictionary.md) — plain-English meaning of every table/column.

---

## 0. What transfers (and what doesn't)

**Transfers:** all 16 application tables and their data (see the dictionary).

**Does NOT transfer automatically — needs re-implementation in MS SQL / Azure:**
- **Auth/identity** — currently Supabase Auth (`auth.users`). `profiles.id` points at it.
- **Row Level Security policies** — re-do as MS SQL roles/grants (see guide §5).
- **DB functions, triggers, cron** — re-do as stored procs / Agent jobs (guide §6).
- **File storage** — `community_files.storage_path` points into Supabase Storage; the file blobs need a new home (e.g. Azure Blob Storage).

---

## 1. Pre-flight: confirm the source data is clean

Run these read-only checks against the live Supabase DB and confirm the expected results before exporting:

```sql
-- (a) No orphaned cross-tags (should be 0)
SELECT count(*) FROM note_tags nt WHERE
   (nt.tag_type='sensor'    AND NOT EXISTS(SELECT 1 FROM sensors     s WHERE s.id=nt.tag_id))
OR (nt.tag_type='community' AND NOT EXISTS(SELECT 1 FROM communities c WHERE c.id=nt.tag_id))
OR (nt.tag_type='contact'   AND NOT EXISTS(SELECT 1 FROM contacts    k WHERE k.id::text=nt.tag_id));

-- (b) Row counts per table (record these; re-check after load to verify nothing dropped)
SELECT 'sensors' t, count(*) FROM sensors UNION ALL
SELECT 'communities', count(*) FROM communities UNION ALL
SELECT 'contacts', count(*) FROM contacts UNION ALL
SELECT 'notes', count(*) FROM notes UNION ALL
SELECT 'note_tags', count(*) FROM note_tags UNION ALL
SELECT 'comms', count(*) FROM comms UNION ALL
SELECT 'comm_tags', count(*) FROM comm_tags UNION ALL
SELECT 'audits', count(*) FROM audits UNION ALL
SELECT 'collocations', count(*) FROM collocations UNION ALL
SELECT 'service_tickets', count(*) FROM service_tickets UNION ALL
SELECT 'install_history', count(*) FROM install_history UNION ALL
SELECT 'community_files', count(*) FROM community_files UNION ALL
SELECT 'community_tags', count(*) FROM community_tags UNION ALL
SELECT 'app_settings', count(*) FROM app_settings UNION ALL
SELECT 'allowed_emails', count(*) FROM allowed_emails UNION ALL
SELECT 'profiles', count(*) FROM profiles
ORDER BY t;
```

---

## 2. Build the MS SQL schema

Use `schema/current-schema.sql` as the blueprint and apply the type map from the
migration guide (§1). Create the 16 base tables **plus** these child tables that
replace PostgreSQL array columns (guide §2):

| New child table | Replaces |
|---|---|
| `sensor_status(sensor_id, status)` | `sensors.status` |
| `contact_communities(contact_id, community_id)` | `contacts.communities` |
| `collocation_sensors(collocation_id, sensor_id)` | `collocations.sensor_ids` |
| `service_ticket_sensors(ticket_id, sensor_id)` | `service_tickets.sensor_ids` |

The two `merged_sf_ids` arrays (notes/comms) are provenance-only — keep them as a
single `NVARCHAR(MAX)` JSON/CSV column rather than a child table.

Create FKs and the PK/unique/filtered indexes per `current-schema.sql`. Defer the
self-referencing `communities.parent_id` FK until after the communities load.

---

## 3. Export the data from Supabase

**Option A — full SQL dump (recommended for a faithful copy).** With the project's
Postgres connection string (Supabase Dashboard → Project Settings → Database):
```
pg_dump --data-only --schema=public --no-owner --no-privileges \
        "<CONNECTION_STRING>" > adec_data.sql
```
Then transform types/arrays for MS SQL, or load into a staging Postgres and use a
Postgres→MSSQL tool (e.g. SSMA for PostgreSQL).

**Option B — per-table CSV.** In the Supabase SQL editor, `SELECT * FROM <table>;`
then **Export → CSV** for each table. Simple, but you must handle the array/JSON
columns (next step) and re-type during `BULK INSERT`.

**For the array columns, export the already-expanded child rows** with these
queries (one row per element — load straight into the §2 child tables):
```sql
SELECT id AS sensor_id,     unnest(status)      AS status        FROM sensors      WHERE status      <> '{}';
SELECT id AS contact_id,    unnest(communities) AS community_id  FROM contacts     WHERE communities <> '{}';
SELECT id AS collocation_id,unnest(sensor_ids)  AS sensor_id     FROM collocations WHERE sensor_ids  <> '{}';
SELECT id AS ticket_id,     unnest(sensor_ids)  AS sensor_id     FROM service_tickets WHERE sensor_ids <> '{}';
```

---

## 4. Transform during load

- **uuid** → `UNIQUEIDENTIFIER` (values copy as-is).
- **timestamptz** lifecycle columns (`created_at`, `updated_at`, `closed_at`,
  `deleted_at`, `*_upload_date`) → `DATETIMEOFFSET`, copy as-is (true instants).
- **`notes.date` / `comms.date`** → see guide §10a: re-interpret the stored UTC
  wall-clock as **America/Anchorage** so they become true instants.
- **jsonb** and the JSON-as-text columns (`audits.notes`, `collocations.notes`,
  `service_tickets.quant_notes`, the `analysis_*` JSON) → `NVARCHAR(MAX)`,
  validate with `ISJSON()`.
- **text dates** (`*_date`, `date_installed`, etc.) → keep as text, or `TRY_CAST`
  to `DATE` where a single ISO value (guide §10b).
- **boolean** → `BIT`.

---

## 5. Load order (parents first, FKs satisfied)

1. `profiles` (after identity is set up)
2. `communities` — load all rows, then enable the `parent_id` self-FK
3. `sensors`, `contacts`
4. `notes`, `comms`, `audits`, `collocations`, `service_tickets`, `install_history`,
   `community_files`, `community_tags`, `app_settings`, `allowed_emails`
5. Link / child tables: `note_tags`, `comm_tags`, `sensor_status`,
   `contact_communities`, `collocation_sensors`, `service_ticket_sensors`

---

## 6. Post-load validation

- Re-run the §1(b) row counts against MS SQL and compare to the recorded source counts.
- Confirm the expanded child tables sum to the source array element counts, e.g.:
  ```sql
  -- source (Postgres): total status elements
  SELECT sum(cardinality(status)) FROM sensors;
  -- target (MS SQL): should match
  SELECT count(*) FROM sensor_status;
  ```
- Spot-check a few records end-to-end (a sensor with several statuses, a note with
  multiple tags, a contact in multiple communities).
- Re-run the orphan-tag check (§1a) adapted to MS SQL — expect 0.

---

## 7. Application cutover

The front end (this repo's `index.html` / `app.js` / `supabase-client.js`) talks to
Supabase via the `db` helper in `supabase-client.js`. If the app itself is being
kept, that single file is where all data access lives — repointing it at a new
backend/API is the integration surface. If the State is rebuilding the UI, this
repo serves as the functional reference and the schema/dictionary are the spec.
