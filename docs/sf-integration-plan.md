# Salesforce → App Integration Plan

Working spec for migrating the historical Salesforce data into the ADEC Sensor Network
Tracker. This is the source of truth for the migration; update it as decisions change.

**Status:** Draft — awaiting full Salesforce data export.
**Owner:** Ayla. **Approach approved:** community-by-community, review-and-approve, every
imported record tagged.

---

## 1. Goals & principles

- **Transparency, accessibility, organization** for all historical records.
- **Community-by-community**, not record-type-by-record-type. During review you see
  everything for one community at once (contacts, sensors, comms, sensor history), work it
  to completion, then move on.
- **Nothing is a blind 1:1 copy.** Salesforce data is messy and mis-typed; we re-classify
  and clean *during* review, not after.
- **Less duplication.** Collapse Salesforce's redundant structure into the app's normalized
  model, and dedupe records as we go.
- **Every imported record is tagged** as a Salesforce import — queryable and reversible.
- **Structured feature tables stay pure.** `service_tickets` and `audits` are for rich
  go-forward workflows. Thin historical free-text does **not** get forced into them.

---

## 2. What the Salesforce data actually looks like

From inspecting a representative Account page ("Glennallen - BLM"):

- **The structured objects are empty.** Assets (0), Serviced Assets (0), Work Orders (0),
  Cases (0). The team never used Salesforce's built-in sensor/issue objects.
- **All real history lives in the Activity timeline as free text**, and the activity *type
  is unreliable*:
  | What it actually is | How SF logged it | Example subject |
  |---|---|---|
  | Email | "logged a call" | "Email to Jake about sensor shutoff issue" |
  | Phone call | logged a call | "Call" |
  | Device issue | "had an event" | "Mod_466 PM sensor issue" |
  | Audit | "had an event" | "Sensor audit (7 days)" |
  | Install | "had an event" | "Sensor 466 installed" |
- **Sensors are text, not records.** "Mod_466" / "Sensor 466" appear only inside subjects.
- **Artifacts are double-listed.** The same `.msg` email shows in both "Notes & Attachments"
  and "Files."
- **Contact status is crammed into names.** e.g. "Mike Sondergaard NO LONGER A CONTACT."
- **Accounts conflate community + org.** "Glennallen - BLM"; the account list mixes true
  communities with organizations (Doyon Ltd, ANTHC, Galena Interior Learning Academy).

**Implication:** the migration is driven by **reading subject lines and re-classifying**,
not by trusting Salesforce's record types.

---

## 3. Target model & routing

Two destinations only. Structured feature tables are intentionally left out of the import.

| Salesforce record | → App destination | Notes |
|---|---|---|
| Email (however logged) | `comms` (`comm_type='Email'`) + `comm_tags` | corrected type |
| Phone call | `comms` (`comm_type='Phone'`) + `comm_tags` | |
| Site visit / text / other comm | `comms` (corrected `comm_type`) + `comm_tags` | |
| Device / sensor issue | `notes` (`type='Sensor Issue'`) + `note_tags` → sensor (+community) | **not** service_tickets |
| Historical audit / collocation | **`audits`** (real record) + manual Excel/DQI upload | see §4 |
| Install / deployment | `notes` (`type='Installation'`) + `note_tags` → sensor | may also backfill `sensors.date_installed` |
| General / misc | `notes` (`type='General'`) + `note_tags` | |
| `.msg` / attachments | `community-files` storage (deduped) | linked to the community |
| Org-only accounts (BLM, Doyon, ANTHC…) | **skipped** | per decision |

`comms.comm_type` and `notes.type` are free-text, so new values need no schema change —
just convention.

---

## 4. Routing decisions

**Device issues → lightweight notes, not service tickets.** `service_tickets` is reserved for
real go-forward repair/RMA workflow. Historical "Mod_466 PM sensor issue" entries become
`notes` (`type='Sensor Issue'`) cross-tagged to the sensor (+community).

**Historical audits → real `audits` records, built from a dedicated ZIP of audit files —
NOT from the Salesforce timeline.** The audit Excel sheets are the authoritative source
(community, pods, dates, and the DQI data all in one place), far richer than the vague
"Sensor audit (7 days)" timeline entries. So audits get their own track:

1. **Ayla provides a ZIP of all audit records** (the audit Excel sheets) → `sf-export/audits/`.
2. A dedicated audit importer parses each file and creates a real `audits` row with its
   metadata (community, sensor/pods, dates), tagged `source='excel_import'` (these come from
   audit Excel sheets, not Salesforce).
3. It **pulls the DQI table from each Excel** into `analysis_results` so each audit renders in
   the **same DQI table format** as go-forward audits (`renderAnalysisResults`).
4. The SF activity-timeline "audit" entries are then **ignored** during the community review
   (the ZIP is the source of truth), avoiding duplicate audit records.

> **OPEN — need one sample audit file** to lock the parser: the existing pipeline
> (`parseAuditData`, `app.js:9036+`) parses *raw AirVision hourly data* and computes the
> regression. The historical audit sheets may instead already contain a *finished DQI/summary
> table*, which needs a different "read the DQI table directly" parser. Also need to confirm
> how each file encodes community / pod IDs / dates (filename convention? a header cell?).

So the rule is: **comms for communications; notes for issues/installs/general; real `audits`
rows built from the audit-records ZIP.**

---

## 5. Subject-line classifier

Each Salesforce activity is auto-classified from its subject; the result is a **default the
reviewer overrides** per record.

| If subject matches… | Default destination |
|---|---|
| `email`, `emailed`, `RE:`, `FW:`, `sent` | comm · Email |
| logged as call, no email hint | comm · Phone |
| `site visit`, `visited`, `onsite` | comm · Site Visit |
| `audit`, `collocation`, `colloc` | **`audits` row** · status "Finished, Analysis Pending" (Excel uploaded later) |
| `install`, `installed`, `deploy`, `deployment` | note · Installation |
| `issue`, `problem`, `shutoff`, `offline`, `not reporting`, `PM sensor`, `repair`, `RMA`, `error` | note · Sensor Issue |
| (anything else) | note · General |

**Sensor linking:** extract a sensor token (`Mod_###`, `Mod ###`, `Sensor ###`, bare `###`)
from the subject, normalize it, and match against `sensors.id`. If matched, the record is
cross-tagged to that sensor; if ambiguous, the reviewer picks.

**Contact/community linking:** the activity's parent Account → community; named people in
"logged a call with X" → match to existing `contacts` and cross-tag.

---

## 6. Schema changes (draft migration)

No changes to `service_tickets` (we don't import into it). The changes are additive
provenance/author fields on the tables we *do* write to, plus relaxing two `audits`
constraints so historical audits without pod IDs can be created. Final file goes under
`supabase/migrations/` right before we run it.

```sql
-- DRAFT — Salesforce integration provenance fields
-- Adds source tagging, original SF id, and original author to imported tables.

-- comms
ALTER TABLE comms ADD COLUMN IF NOT EXISTS source     text DEFAULT 'manual';
ALTER TABLE comms ADD COLUMN IF NOT EXISTS sf_id      text;
ALTER TABLE comms ADD COLUMN IF NOT EXISTS logged_by  text DEFAULT '';

-- notes
ALTER TABLE notes ADD COLUMN IF NOT EXISTS source     text DEFAULT 'manual';
ALTER TABLE notes ADD COLUMN IF NOT EXISTS sf_id      text;
ALTER TABLE notes ADD COLUMN IF NOT EXISTS logged_by  text DEFAULT '';

-- community_files (dedupe + provenance for .msg attachments)
ALTER TABLE community_files ADD COLUMN IF NOT EXISTS source text DEFAULT 'manual';
ALTER TABLE community_files ADD COLUMN IF NOT EXISTS sf_id  text;

-- audits (historical audits imported from the audit-records ZIP)
ALTER TABLE audits ADD COLUMN IF NOT EXISTS source text DEFAULT 'manual';
-- Historical audits may lack a travelling audit pod / community pod id.
ALTER TABLE audits ALTER COLUMN audit_pod_id     DROP NOT NULL;
ALTER TABLE audits ALTER COLUMN community_pod_id DROP NOT NULL;

-- Idempotency: a given SF record imports at most once per table.
CREATE UNIQUE INDEX IF NOT EXISTS uq_comms_sf_id
    ON comms(sf_id) WHERE sf_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_notes_sf_id
    ON notes(sf_id) WHERE sf_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_files_sf_id
    ON community_files(sf_id) WHERE sf_id IS NOT NULL;
```

- **`source`** — `'salesforce_import'` on every imported row (default `'manual'`). Lets us
  filter, badge, and cleanly **reverse** a bad batch.
- **`sf_id`** — original Salesforce record id → traceability + safe re-runs.
- **`logged_by`** — original SF author (e.g. "Isaac Van Flein"), since they aren't app users
  and `created_by` can't hold them.
- **UI:** show a "Salesforce Import" badge on these records, like the existing collocation
  one (`app.js:11528`).

---

## 7. Dedup & cleanup rules

- **Files:** dedupe the `.msg`/attachment double-listing by `filename + size`.
- **Comms:** dedupe by `sf_id`; additionally flag near-duplicates (same date + subject +
  contact, e.g. the two May 13 "Mike Sondergaard" calls) for merge/skip in review.
- **Contacts (already migrated):** audit for the "NO LONGER A CONTACT"-in-name pattern; set
  `active=false` and restore the clean name. Tracked as a side task.
- **Re-runs are safe:** the `sf_id` unique indexes prevent duplicate inserts.

---

## 8. Per-community review workflow (the importer)

A standalone page (scaffolded from `archive/sf-contact-migrator.html` — same Supabase
bootstrap, login, navy/gold theme):

1. **Account → community map.** Build the mapping (skip org-only accounts). Reviewer can
   correct any mapping.
2. **Community picker** with progress: "Community 12 of 43 · 8 records pending."
3. **Per community:** show existing contacts for context, then the classified record list.
   Each record card shows the raw Salesforce data beside the proposed app record, with
   editable **type / sensor / contact tags / date / author**, and **Approve / Edit / Skip**.
4. **Dry-run first** — show what *would* be written before committing.
5. On approve, write via `db.*` helpers with `source='salesforce_import'` + `sf_id`, tagged.
6. Visible status log; nothing writes until approved.

---

## 9. Execution sequence

1. **Ayla:** run Setup → Data Export → Export Now ("include all data" + attachments); drop
   the ZIP in `sf-export/`. *(Raw export is git-ignored.)*
2. **Claude:** unzip, inventory the CSVs, and produce the concrete **Account → community
   map** + a sample of classified records for sign-off.
3. **Ayla:** approve the mapping, the classifier defaults, and §6 schema changes.
4. **Claude:** run the migration; build the per-community importer.
5. **Ayla:** review & approve community by community; approved records write in, tagged.
6. **Later:** reuse the same machinery for any remaining record types.

---

## 10. Open items

- [ ] **Audit Excel format** (§4): does each historical audit file contain a *finished DQI
      table* (needs a "read DQI table" parser) or *raw AirVision hourly data* (existing
      `parseAuditData` works)? — pending one sample file.
- [ ] How each audit file encodes its community / pod IDs / dates (filename vs. header cell).
- [ ] Sensor-id format in `sensors.id` vs. subject tokens ("Mod_466") — confirm match rule
      once the export is in hand.
- [ ] Whether installs should also backfill `sensors.date_installed`.
- [ ] Contacts cleanup pass for "NO LONGER A CONTACT" names.

---

## 11. Tracks (parallel workstreams)

The migration splits into two independent tracks:

- **Track A — Audits.** Driven by the audit-records ZIP (`sf-export/audits/`). Dedicated
  importer → real `audits` rows + DQI tables. **In progress** — 23 files analyzed.

  **Findings (23 audit `.xls` files):**
  - Each file holds raw hourly paired data **and** a pre-computed DQI table. We **pull the DQI
    table** (faithful to the signed reports) rather than recompute — the app's first-24h
    exclusion makes recomputed numbers diverge from the official reports (e.g. Badger PM10
    R² 0.955→0.075). Historical imported audits therefore **bypass the first-24h trim**.
  - DQI table location varies by vintage (`Sheet1` / `RESULTS` / `Hour Data` / `Graphs`);
    located by header (`Factor` + `R2`/`Slope`/`Intercept`, plus `SD`/`RMSE` on newer files).
  - **22/23 auto-extract.** Only **Tyonek** (audit 460 / pod 469) lacks a finished table →
    flag for manual completion or skip. Two older files (Badger Dec-2024, Glennallen Apr-2025)
    lack SD/RMSE. Filenames encode audit pod / community / community pod / dates / status, but
    **Ketchikan** (no community pod #) and **Skagway** (no audit pod #) need manual fill.
  - **Dedupe against the app:** the importer loads existing `audits` and **skips any file whose
    community + audit date already exists on the app** (date-specific match), so audits already
    entered aren't duplicated.
  - **Multiple DQI tables per file:** 4 files contain both an original and a corrected table
    (`Graphs` + `Graphs - Spikes Removed`, `Graphs` + `Modified Graphs`, `Hour Data` +
    `Hour Data Edited`, `Hour Data` + `Graphs`). The importer extracts **all** tables, defaults
    to the corrected one, and shows a **per-card sheet picker** so the exact official numbers can
    be confirmed before approving. (Cordova/Kodiak PM2.5 and Goldstream CO differ between sheets.)
  - **Status:** imported audits get the terminal status **`Complete, Excel Analysis`** (registered
    in app.js so it renders as a green/done badge and its own Audits column) to distinguish them
    from go-forward audits. A **Reset** button deletes all importer-created audits
    (`source='excel_import'`) and their uploaded Excels so the batch can be re-run cleanly.
- **Track B — Communities (comms, notes, files).** Driven by the full Salesforce Data Export
  (`sf-export/full-export/`). Per-community review importer. SF "audit" timeline entries
  ignored here (audits come from Track A's Excel ZIP).

  **Findings (full export inventory):**
  - **Task.csv (1,728)** — but **1,336 are bulk `List Email:`** stakeholder blasts (→ exclude or
    treat as a separate outreach log). The **392 real tasks** classify as ~303 Phone, ~64 Email,
    ~24 notes/other → mostly **comms**.
  - **Event.csv (910)** — device service history: ~331 Sensor Issue/Service, ~246 Installation,
    ~160 General, ~151 Audit (skip — Track A), ~22 comms → mostly **notes** tagged to sensor +
    community.
  - **Notes** — 285 `SNOTE` records (Salesforce Notes) → `notes`.
  - **Files** — 78 PDF, 74 JPG, 2 PNG, 1 MSG, 1 XLSX, 1 DOCX (via ContentVersion +
    ContentDocumentLink) → `community-files` storage (photos may tag to audits/community).
  - **Account.csv (150)** typed: **63 `Community`** + orgs/places (Tribe 20, Library 10,
    School 9, Native Corporation 6, …) → account→community map; "ignore org accounts" = skip pure
    orgs, but map gathering-place accounts (Library/School/Museum) to their community.
  - **Contact (212)** already migrated → map `WhoId`; **User (35)** → `logged_by` author names.
  - **Community linkage is partial** (e.g. 667 events have no account) → the review tool must let
    the reviewer assign/confirm the community per record, defaulting from account → subject text →
    contact.
  - **Most activities link to an Asset, not text.** **660 of 910 events** (and a few tasks) have
    `WhatId` = an **Asset** (the sensor), so the sensor reference lives in the relationship, not
    the subject. Salesforce Assets name the QuantAQ pods **`QuantAQ_00466`** → app sensor
    **`MOD-00466`** (AQMesh/PurpleAir assets are older, not in the app). The preprocessor maps each
    activity's Asset → sensor (and the Asset's `AccountId` → community), lifting notes-with-sensor
    from ~54 (subject text only) to **373**. The regeneration script is
    `sf-export/build-import-data.py` (local; reads the export CSVs + live Asset/ContentNote pulls).
  - **Migration:** `20260603130000_sf_comms_notes_provenance.sql` (source / sf_id / logged_by on
    comms + notes + files, with sf_id unique indexes for safe re-runs).
