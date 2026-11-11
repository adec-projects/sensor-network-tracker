# Transition & Handoff Plan

**Prepared for the DEC handoff meeting, Friday Nov 6, 2026, 8:30 AM.**
Ayla's last day is approximately **Nov 18, 2026** (about two weeks out).

This document is the people-and-access plan for handing the Sensor Network Tracker
off to DEC. It sits on top of the technical migration docs that already exist in
this repo (see the [Document map](#document-map) at the bottom). Those cover how to
move the data into a database like SQL Server. This document covers the part those
don't: who owns what today, the risk that creates, and exactly what has to happen
before Ayla leaves.

---

## 1. The one thing to take away from the meeting

> **Update, Nov 6, 2026: this risk has been addressed.** DEC's contact is now an
> **Owner** of the `adec-projects` GitHub organization and an Owner/Administrator of the
> Supabase project, and has confirmed they can log in to both. DEC can make its own
> up-to-date backup at any time with `scripts/backup-database.sh` (section 5), so no
> copy needs to be handed over. The rest of this section is kept as the original
> reasoning.

**Everything this app runs on is tied to Ayla's personal accounts, and Ayla is the
only person with access.** When her access ends, DEC loses the ability to get into
the code and the live database unless we act first.

DEC's decided direction is to **migrate the data into DEC's own internal database
and retire this app.** That makes the single most important action clear:

> **Get a complete, verified copy of the data into DEC's hands before Ayla's last
> day.** That export is the safeguard. Even if every account lapses the day she
> leaves, the data is safe and the migration can proceed on DEC's own schedule.

Everything else below supports that one goal.

---

## 2. What the system is

Two pieces, no server to maintain:

1. **The website** (what staff use) is a set of plain files hosted free on GitHub
   Pages at <https://adec-projects.github.io/sensor-network-tracker/>.
2. **The database** (where all the data lives) is a free Supabase project. Supabase
   also handles logins and stores uploaded files.

There is no custom server, no monthly bill, and no automatic sensor/QuantAQ
connection anymore. Staff log issues by hand. This simplicity helps the
handoff: the valuable thing to preserve is **the data**, and the data all lives in
one place (Supabase).

---

## 3. Access and ownership inventory

*As of Nov 6, 2026, DEC's contact also has Owner-level access to the GitHub organization and the Supabase project (see section 1). The table shows the situation before that.*

This is the "who holds the keys" table. Walk DEC through it.

| What | Where it lives | Who controls it today | Risk when Ayla leaves | Action needed |
|---|---|---|---|---|
| **The code** | GitHub org `adec-projects`, repo `sensor-network-tracker` | **Ayla's personal GitHub `aylacrosby531` is the only member and only owner** | **High. No one else can get in.** | Add a DEC-owned GitHub account as an org **Owner** before departure, or export the repo as a zip for DEC's records |
| **The live website** | GitHub Pages (auto-published from the code) | Same GitHub org as above | High (same account) | Covered by the GitHub action above |
| **The database + all data** | Supabase project `uejryzioxogquflijgyf` | **Ayla's personal Supabase login** | **High. This is where the data is.** | **Export the data (section 5).** Optionally transfer the Supabase project to a DEC-owned login |
| **Logins / user accounts** | Supabase Auth (inside the same project) | Same Supabase login | High | Does not migrate as-is; DEC's new system will have its own logins. The list of who had access is preserved in the export (`profiles`, `allowed_emails`) |
| **Uploaded files** | Supabase Storage bucket `community-files` | Same Supabase login | Medium | Download the bucket contents separately (section 5, step 4) |
| **Keep-the-database-awake job** | GitHub Action `keepalive.yml` in the repo | Same GitHub org | **Medium.** GitHub switches scheduled jobs off after 60 days with no commits (this happened Oct 21 - Nov 5, 2026). If it's off for 7+ days with nobody using the app, Supabase pauses the database. | While Supabase is the live system, check GitHub → **Actions** → *Supabase keep-alive* about monthly; if it shows as disabled, click **Enable workflow**, then **Run workflow**. Irrelevant once migrated |
| **Secret keys / passwords** | Supabase dashboard (database password, service key) | Ayla only | High | Hand over in person/securely at the end, or rotate after transfer. **Never put these in this repo or an email** |
| **QuantAQ sensor vendor** | n/a | n/a | None | No live integration exists. Nothing to transfer |

**Note:** the "anon key" that appears in the code is meant to be public and is
safe. It is not a password. The real secrets (database password, service key) are
only in the Supabase dashboard and must be handed over carefully.

---

## 3a. Bringing the remaining Salesforce records over

Salesforce and the app are used side by side for a while. The **Salesforce Transfer page**
brings new Salesforce notes, communications, audits, sensors, and contacts into the app,
**without duplicates**, and shows only records created since the last transfer. It's a
single web page; nothing to install:

* **Open it:** <https://adec-projects.github.io/sensor-network-tracker/tools/sf-transfer/>
  (or double-click `tools/sf-transfer/index.html` in a downloaded copy of the repo).
* **Needs:** a Salesforce Data Export ZIP (a Salesforce admin requests it in Setup) and an
  **admin** login to the app. Instructions: [`tools/sf-transfer/README.md`](tools/sf-transfer/README.md).
* **How it works:** sign in, choose the ZIP, then review community by community and click
  **Approve** (saved immediately) or **Skip**, like the spring 2026 importer.

**Status (Nov 10, 2026):** Ayla is running it on a current Salesforce export the week of
Nov 10. It can be run again later with a newer export: set the date at the top of the page
to the date of the previous transfer.

**After that transfer, enter new information in the app.** Anything entered only in
Salesforce after the export date won't be in the app unless the page is run again.

## 3b. Day-to-day account help (no IT ticket needed)

All of this happens inside the app, in **Settings → Users**, by any Admin. There is
no email-based reset, so nothing depends on an outside email service.

| Problem | Fix |
|---|---|
| Forgot password | Admin clicks **Reset password**, then reads the one-time temporary password to the person by phone or Teams. They sign in with it and must choose a new password. |
| Switching to a new phone (can still sign in) | The person clicks **Reset MFA** next to their **own** name in Settings → User Management, confirms with their password, and sets up the new phone at next sign-in. No admin needed. |
| Lost phone (can't sign in) | Admin clicks **Reset MFA** on that person's row. The person sets up the authenticator again at next sign-in. |
| Wants to change their password | The person clicks **Reset password** next to their **own** name (current + new password). No admin needed. |
| Both | Use both buttons. |
| Person leaves | **Archive** them. The database blocks their access immediately, even if they remember their password. |
| All admins unavailable | Last resort, by a Supabase project owner in the dashboard: to fix a lost authenticator, delete the user's MFA factor (Authentication → Users). To restore admin access, make a trusted person an admin in the SQL Editor: `UPDATE allowed_emails SET role = 'admin' WHERE email = '…'; UPDATE profiles SET role = 'admin' WHERE email = '…';` That admin can then use **Reset password** in the app. |

How this is enforced is described in `SECURITY.md` ("Sign-in rules enforced by the
database") and `ARCHITECTURE.md` (Authentication).

---

## 4. The migration path (data into DEC's database)

The heavy technical lifting is **already documented** in this repo, written for
exactly this move (Supabase/PostgreSQL to Microsoft SQL Server, which is what the
State typically uses). DEC's database person should start with these:

- **`schema/current-schema.sql`** - the exact structure of all 16 tables, with notes
  on translating each piece to SQL Server.
- **`docs/data-dictionary.md`** - plain-English meaning of every table and column.
- **`docs/mssql-migration-guide.md`** - how PostgreSQL features map to SQL Server
  (data types, the "list" columns, dates, logins).
- **`docs/mssql-migration-runbook.md`** - the actual step-by-step transfer and how
  to verify afterward that nothing was dropped.

**Plain-English summary for the meeting:** there are 16 tables. Most copy over
directly. A handful of fields hold a *list* of values in one cell (for example a
sensor can have several statuses at once), and SQL Server handles those a little
differently, so those become small side tables. A few date and note fields are
stored as text and carry a conversion note. All of this is spelled out in the guide
and runbook, with checks to confirm the row counts match after loading.

DEC's team does **not** need to understand the website code to do the migration.
The schema and the data export are the whole spec.

---

## 5. The data export (the safeguard) - do this before the last day

This is the most important deliverable. Two ways to do it; **Option A is the full,
faithful backup and is recommended.** Option A needs the database password (Supabase
dashboard → Project Settings → Database; the project owner has it or can reset it).
Option B only needs a login to the Supabase dashboard.

### Option A: one complete backup file (recommended)

A ready-to-run script is in this repo: **`scripts/backup-database.sh`**. It uses the
standard PostgreSQL tools (`brew install libpq` on a Mac; no Docker needed) and
produces a timestamped folder with the full schema and all the data. Run it from the
project folder:

```
./scripts/backup-database.sh
```

It will ask for the database password, then write a `handoff-backup-<date>/` folder
containing `schema.sql`, `data.sql`, and a `row-counts.txt` you can compare against
after DEC loads it. Hand that folder to DEC (secure file share or a drive, not
email, since it contains contact details).

### Option B: table-by-table spreadsheets (no tools, just the website)

If you'd rather not run anything: in the Supabase dashboard, open the **SQL Editor**,
run `SELECT * FROM <table>;` for each of the 16 tables, and click **Export → CSV**.
The 16 table names are listed in the runbook. This gives DEC 16 spreadsheets. It is
simpler but you have to do each table by hand, and the "list" columns need the extra
expansion queries from the runbook section 3.

### Step 4 (either option): the uploaded files

Separately, download the contents of the Supabase Storage bucket named
**`community-files`** from the dashboard (Storage → community-files → download).
These are files staff attached to communities. Keep them with the backup.

### Before exporting, a 2-minute cleanliness check

The runbook (section 1) has a few read-only SQL checks that confirm the data is
clean before you copy it. Worth running so DEC starts from a tidy copy. They are
copy-paste ready in the runbook.

---

## 6. Decisions to get from DEC in the meeting

Bring these as your agenda. Each one is a decision only DEC can make:

1. **Who is the receiving owner?** Name a specific DEC person (ideally someone in IT
   or with database access) who will hold the handoff. *Nobody is named yet, so this
   is decision #1.* Until there is a name, the data export is what protects DEC.
2. **Target system and timeline.** Confirm the data is going into SQL Server (or
   which system), and roughly when. That sets how urgent the live-account transfer is.
3. **Who receives the data export and where does it go?** A DEC network drive, a
   secure share, DEC IT? Decide the destination before Ayla produces it.
4. **Interim access while migrating.** Does DEC want to keep the live app running
   during the transition (keep logging in the meantime), or freeze it on a date? If
   keeping it live, someone DEC-owned should become a GitHub org Owner and a Supabase
   project member now.
5. **Decommission date.** When does the free Supabase project get shut down? The
   runbook recommends keeping it read-only for 30 to 60 days *after* a successful
   migration as a fallback, then closing it.
6. **Credential handover method.** Agree how the real passwords/keys get to DEC
   securely on Ayla's last day (in person, or DEC resets them after she transfers the
   accounts). Not by email, and not in this repo.

---

## 7. Two-week action checklist

**Ayla, this week:**
- [ ] Walk DEC through this document in the meeting and get the six decisions above.
- [x] Run the data export (section 5). *Done Nov 6, 2026: `handoff-backup-20261106/` on Ayla's laptop; all 16 tables.*
- [ ] Run the pre-export cleanliness check (runbook section 1).
- [ ] Download the `community-files` storage bucket.
- [x] ~~Deliver the export + files to DEC.~~ *Not needed: DEC has direct access and can run the backup itself.*
- [ ] Make a plain zip of this whole code repo as a backup for DEC's records.

**Ayla, before the last day (once DEC names a receiver):**
- [x] Add DEC's GitHub account as an **Owner** of the `adec-projects` org. *Done Nov 6, 2026; access confirmed.*
- [x] Add DEC's login to the Supabase project (Owner/Administrator). *Done Nov 6, 2026; access confirmed.*
- [x] ~~Hand over the database password and keys.~~ *Not needed: DEC's Supabase owner can
      reset the database password and see the keys in the dashboard.*
- [x] ~~Confirm DEC has opened the export.~~ *Not needed (see above).*
- [x] Make sure at least two DEC staff are app **Admins** (Settings → Users). *Done Nov 6, 2026.*
- [ ] On Ayla's last day, a **DEC admin** (you can't remove your own account) handles
      Ayla's app accounts in Settings → Users:
      - the personal Gmail test account: **Delete** (test only);
      - the alaska.gov work account: **Archive**, not Delete. Archiving blocks all access
        immediately but keeps Ayla's name on the records she created; Delete would
        relabel all of them "[Deleted User]".
- [x] Delete the `snt-transfer-test` Supabase project (test copy; holds contact data). *Done Nov 6, 2026.*
- [x] Delete local copies of app/Salesforce data from Ayla's laptop
      (`handoff-backup-20261106/`, `~/sf-transfer-work/`, `sf-export/`). *Done Nov 6, 2026.*

**DEC, after handoff:**
- [ ] When ready to migrate: make a fresh backup (`scripts/backup-database.sh`), load it
      into the target system following the runbook, and run the after-load row-count
      check to confirm nothing dropped.
- [ ] If Salesforce is still being used after Ayla's transfer: run the Salesforce Transfer page
      (`tools/sf-transfer/`) once more just before Salesforce access ends.
- [ ] Keep Supabase read-only for 30 to 60 days as a fallback, then decommission.
- [ ] After Ayla leaves: remove her from the GitHub organization and the Supabase project,
      and reset the Supabase database password (she knows the current one).

---

## 8. If DEC can't name a technical owner in time

This is the realistic worst case, so plan for it: if no DEC person is ready to take
the live accounts before Ayla's last day, that is **survivable as long as the data
export and the repo zip are delivered.** The app can keep running untouched on the
existing accounts for a while (it costs nothing), and DEC does the migration from the
export whenever their database person is ready. The accounts become a cleanup item,
not a data-loss emergency. The export is what turns "we lost access" into "we have
everything we need."

---

## Document map

| Doc | What it's for |
|---|---|
| **TRANSITION.md** (this file) | People, access, and the meeting plan |
| `HANDOFF.md` | Index to the technical migration docs |
| `schema/current-schema.sql` | Exact database structure, with SQL Server notes |
| `docs/data-dictionary.md` | What every table and column means |
| `docs/mssql-migration-guide.md` | PostgreSQL to SQL Server translation |
| `docs/mssql-migration-runbook.md` | Step-by-step transfer + verification |
| `SECURITY.md` | How access/permissions work |
| `ARCHITECTURE.md` | How the website and database fit together |
| `README.md` / `docs/developer-notes.md` | Project overview and file map |
| `scripts/backup-database.sh` | One-command data export |
| `scripts/make-test-copy.sh` | Copies the live app into an empty test project |
| `supabase/rollback/` | Emergency undo for the sign-in security rules |
| `tools/sf-transfer/` | Salesforce Transfer page and its instructions |
