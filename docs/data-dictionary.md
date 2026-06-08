# Data Dictionary: ADEC Sensor Network Tracker

Describes the purpose and semantics of every table and column: the business
meaning the DDL alone doesn't convey. Complements
[`schema/current-schema.sql`](../schema/current-schema.sql) (exact types, keys,
indexes) and [`docs/mssql-migration-guide.md`](mssql-migration-guide.md)
(type/feature mapping).

**Conventions used throughout:**
- **`id`** is the primary key of every table.
- **`created_at` / `updated_at`** are timestamps (with time zone) for when a row
  was created / last changed.
- **`created_by` / `updated_by` / `deleted_by` / `archived_by`** hold the *app
  user* (a `profiles.id`) who did that action. They're nullable.
- **Soft delete:** most record tables aren't hard-deleted. `notes`, `comms`,
  `audits`, `collocations`, `service_tickets` use a `deleted_at` timestamp (a
  "trash bin", so non-null means deleted). `sensors` use an `active` flag
  (active vs. archived) instead, because physical inventory reads better that way.
- **Salesforce provenance:** rows imported from the old Salesforce system carry
  `source = 'salesforce_import'` (vs. `'manual'`), the original `sf_id`, and
  `logged_by` (the original Salesforce author, who is not an app user).

---

## Core entities

### `communities`
The ~40 Alaska communities plus the 3 regulatory sites and the lab locations.
- `id`: a short readable code, e.g. `bethel`, `anc-garden`, `fbx-ncore`.
- `name`: display name, e.g. "Bethel".
- `parent_id`: points to another community when this is a **sub-community**
  (e.g. a specific school site under a district). Null for top-level communities.
- `active`: false hides a community without deleting it.
- `details`: free-text notes/details shown on the community page.
- `network_availability`: free-text note about cellular/network coverage there.

### `sensors`
The physical air-quality pods (QuantAQ Modulairs and a few other low-cost sensors).
- `id`: the pod label. **3-digit pods are `MOD-00xxx`; 4-digit pods are
  `MOD-X-PM-0xxxx`** (the "X-PM" part is significant, so keep it).
- `soa_tag_id`: the State of Alaska asset-tag number.
- `type`: `Community Pod`, `Permanent Pod`, `Audit Pod`, or `Not Assigned`.
- `status`: a **list** of status labels (a pod can hold several at once, e.g.
  "Online" + "SD Card Issue"). See "List columns" note below.
- `community_id`: which community the pod is currently at (null = unassigned/lab).
- `location`: street address or GPS coordinates of the install.
- `date_purchased`, `date_installed`, `collocation_dates`: dates, stored as text.
- `details`: free-text notes shown on the sensor page.
- `active` / `archived_at` / `archived_by`: soft-delete (active vs. retired pod).

### `contacts`
People at each community (and some non-community contacts).
- `name`, `role`, `org`, `email`, `phone`: the person's details.
- `community_id`: their first/primary community (kept for back-compat).
- `communities`: a **list** of all community ids this contact serves (a contact
  can cover several sites). This is the authoritative membership.
- `email_list`: true if they should receive group emails.
- `primary_contact`: flagged as a primary contact.
- `active`: false hides them without deleting.

### `profiles`
The application's user accounts. One row per signed-in staff user.
- `id`: matches the Supabase Auth user id (the login identity). **This is the
  one piece tied to Supabase Auth.** On MS SQL it must point at the new identity
  store.
- `email`, `name`: the user's email and display name.
- `role`: `user` or `admin` (admins can manage users, delete records, etc.).

---

## Activity / history

### `notes`
Log entries: issues, installs, moves, status changes, general notes. The heart of
the activity history. A note is linked to sensors/communities/contacts via the
`note_tags` table (see below), so one note can appear in several histories.
- `date`: when the logged event happened.
- `type`: the kind of note (e.g. `General`, `Installation`, `Sensor Issue`,
  `Sensor Move`, `Status Change`).
- `text`: the note title/first line.
- `additional_info`: the note body / details (also stores structured before→after
  data for status-change and move notes, as JSON text).
- `source` / `sf_id` / `merged_sf_ids` / `logged_by`: Salesforce import provenance.
  `merged_sf_ids` is a **list** of duplicate Salesforce ids that were merged into
  this one note during import.

### `comms`
Communications: phone calls, emails, site visits. Same idea as notes but for
contact interactions. Linked via `comm_tags`.
- `comm_type`: `Phone Call`, `Email`, `Site Visit`, etc.
- `subject`, `text`, `full_body`: the communication content.
- `community_id`: the primary community it relates to.
- Salesforce provenance fields as above.

### `note_tags` and `comm_tags`: the cross-reference (link) tables
These connect a note (or comm) to the things it's about. **One row = one link.**
- `note_id` / `comm_id`: which note/comm.
- `tag_type`: what kind of thing this links to: `sensor`, `community`, or
  `contact` (comm_tags only allows `community` or `contact`).
- `tag_id`: the id of that sensor/community/contact.
- **Important:** `tag_id` is a plain text id that means a different table
  depending on `tag_type`. There's intentionally no foreign key on it (the three
  target tables have different id types). The app cleans up dangling links.

### `community_tags`
Free-text **labels** on a community (e.g. "Regulatory Site", "Interior Network").
- `community_id`: which community.
- `tag`: the label text.
- **Naming caution:** despite the similar name, this is unrelated to `comm_tags`.
  "comm" is overloaded: `community_tags` = community labels;
  `comm_tags` = links for *communications*.

### `install_history`
The timeline of which pod was installed at which community and when. One row per
"stay." Drives the Install History display on community pages. Written
automatically whenever a pod is moved.
- `community_id`: where the pod was installed.
- `sensor_id`: which pod.
- `installed_date` / `removed_date`: the stay's start and end (text dates;
  null `removed_date` = still installed).

---

## Field operations

### `audits`
A traveling **audit pod** collocated against a community's pod to validate its
data over ~a week.
- `audit_pod_id` / `community_pod_id`: the two pods being compared (text labels).
- `community_id`: where the audit happened.
- `status`: e.g. `Scheduled`, `Auditing a Community`, etc.
- `start_date` / `end_date`: the audit window (text dates).
- `conducted_by`: who ran it (free text).
- `notes`: a JSON list of progress notes (stored as text).
- `analysis_results` / `analysis_chart_data`: the DQI analysis output (JSON).
- `analysis_name` / `analysis_file_path` / `analysis_file_name` /
  `analysis_upload_date` / `analysis_uploaded_by`: the uploaded analysis file.

### `collocations`
Multi-pod collocation studies (similar to audits but for groups of pods, often at
a lab or regulatory site against a reference monitor).
- `location_id`: **the community/lab where it happened** (note: this column is
  named `location_id`, not `community_id`, the one naming inconsistency in the schema).
- `status`, `start_date`, `end_date`: study state and window.
- `sensor_ids`: a **list** of the pods in the study.
- `permanent_pod_id`: the reference/permanent pod.
- `bam_source`: the reference BAM monitor source.
- `conducted_by`, `notes`, and the `analysis_*` fields: as in audits.

### `service_tickets`
Repair / RMA tickets for sending pods to QuantAQ for service.
- `sensor_id`: the pod (legacy single column).
- `sensor_ids`: a **list** of pods on the ticket (the current multi-pod field).
- `ticket_type`, `status`: e.g. status `Ticket Opened`, `At Quant`, etc.
- `rma_number`, `fedex_tracking_to`, `fedex_tracking_from`: shipping/RMA tracking.
- `issue_description`, `work_completed`: the problem and the fix.
- `quant_notes`: a JSON list of progress notes (the column name is a leftover
  from the old QuantAQ integration; it's just generic progress notes now).
- `closed_at`: when the ticket was closed.

---

## Configuration / access

### `app_settings`
A simple key/value store for app configuration.
- `key`: the setting name (e.g. `mfa_required`, `user_guide_body`).
- `value`: the value as text (can hold a boolean string, JSON, or HTML).

### `allowed_emails`
The signup allow-list. Only emails listed here can create an account, enforced by a
database trigger, not just the browser.
- `email`: the allowed address (unique).
- `role`: the role they'll get (`user` / `admin`).
- `status`: `active` or revoked.
- `can_edit_user_guide`: lets a non-admin edit the in-app user guide.

---

## "List columns" note (important for MS SQL)
Several columns hold a **list of values in one field** (PostgreSQL arrays):
`sensors.status`, `contacts.communities`, `collocations.sensor_ids`,
`service_tickets.sensor_ids`, `notes.merged_sf_ids`, `comms.merged_sf_ids`.
Microsoft SQL Server has no array type: each of these becomes either a small
child table (one row per value) or a delimited/JSON string. The migration guide
covers the recommended approach per column.
