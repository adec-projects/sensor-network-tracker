# Transition & Handoff Plan

**Prepared for the DEC handoff meeting, Thursday Nov 6, 2026, 8:30 AM.**
Ayla's last day is approximately **Nov 19, 2026** (about two weeks out).

This document is the people-and-access plan for handing the Sensor Network Tracker
off to DEC. It sits on top of the technical migration docs that already exist in
this repo (see the [Document map](#document-map) at the bottom). Those cover how to
move the data into a database like SQL Server. This document covers the part those
don't: who owns what today, the risk that creates, and exactly what has to happen
before Ayla leaves.

---

## 1. The one thing to take away from the meeting

**Everything this app runs on is tied to Ayla's personal accounts, and Ayla is the
only person with access.** When her access ends, DEC loses the ability to get into
the code and the live database unless we act first.

DEC's decided direction is to **migrate the data into DEC's own internal database
and retire this app.** That makes the single most important action clear:

> **Get a complete, verified copy of the data into DEC's hands before Ayla's last
> day.** That export is the insurance policy. Even if every account lapses the day
> she leaves, the data is safe and the migration can proceed on DEC's own schedule.

Everything else below supports that one goal.

---

## 2. What the system actually is (30-second version)

Two pieces, no server to maintain:

1. **The website** (what staff use) is a set of plain files hosted free on GitHub
   Pages at <https://adec-projects.github.io/sensor-network-tracker/>.
2. **The database** (where all the data lives) is a free Supabase project. Supabase
   also handles logins and stores uploaded files.

There is no custom server, no monthly bill, and no automatic sensor/QuantAQ
connection anymore. Staff log issues by hand. This simplicity is good news for a
handoff: the valuable thing to preserve is **the data**, and the data all lives in
one place (Supabase).

---

## 3. Access & ownership inventory (the heart of the meeting)

This is the "who holds the keys" table. Walk DEC through it.

| What | Where it lives | Who controls it today | Risk when Ayla leaves | Action needed |
|---|---|---|---|---|
| **The code** | GitHub org `adec-projects`, repo `sensor-network-tracker` | **Ayla's personal GitHub `aylacrosby531` is the only member and only owner** | **High. No one else can get in.** | Add a DEC-owned GitHub account as an org **Owner** before departure, or export the repo as a zip for DEC's records |
| **The live website** | GitHub Pages (auto-published from the code) | Same GitHub org as above | High (same account) | Covered by the GitHub action above |
| **The database + all data** | Supabase project `uejryzioxogquflijgyf` | **Ayla's personal Supabase login** | **High. This is where the data is.** | **Export the data (section 5).** Optionally transfer the Supabase project to a DEC-owned login |
| **Logins / user accounts** | Supabase Auth (inside the same project) | Same Supabase login | High | Does not migrate as-is; DEC's new system will have its own logins. The list of who had access is preserved in the export (`profiles`, `allowed_emails`) |
| **Uploaded files** | Supabase Storage bucket `community-files` | Same Supabase login | Medium | Download the bucket contents separately (section 5, step 4) |
| **Keep-the-database-awake job** | GitHub Action `keepalive.yml` in the repo | Same GitHub org | Low, but it stops if the repo goes quiet | Only matters while the Supabase project is still the live system. Irrelevant once migrated |
| **Secret keys / passwords** | Supabase dashboard (database password, service key) | Ayla only | High | Hand over in person/securely at the end, or rotate after transfer. **Never put these in this repo or an email** |
| **QuantAQ sensor vendor** | n/a | n/a | None | No live integration exists. Nothing to transfer |

**Note:** the "anon key" that appears in the code is meant to be public and is
safe. It is not a password. The real secrets (database password, service key) are
only in the Supabase dashboard and must be handed over carefully.

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

## 5. The data export (the insurance policy) - do this before the last day

This is the most important deliverable. Two ways to do it; **Option A is the full,
faithful backup and is recommended.** Both need the database password from the
Supabase dashboard (Project Settings → Database). Ayla has this.

### Option A: one complete backup file (recommended)

A ready-to-run script is in this repo: **`scripts/backup-database.sh`**. It uses the
Supabase tool that's already installed and produces a timestamped folder with the
full schema and all the data. Run it from the project folder:

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
- [ ] Run the data export (section 5) and the pre-export cleanliness check.
- [ ] Download the `community-files` storage bucket.
- [ ] Deliver the export + files to wherever DEC decides (section 6, #3).
- [ ] Make a plain zip of this whole code repo as a backup for DEC's records.

**Ayla, before the last day (once DEC names a receiver):**
- [ ] Add DEC's GitHub account as an **Owner** of the `adec-projects` org (or confirm
      DEC is OK relying on the exported zip instead).
- [ ] Add DEC's login to the Supabase project, or start a Supabase project-transfer
      to a DEC-owned account.
- [ ] Hand over the database password and keys securely (section 6, #6).
- [ ] Confirm DEC has successfully opened and read the export.

**DEC, after handoff:**
- [ ] Load the export into the target system following the runbook, and run the
      after-load row-count check to confirm nothing dropped.
- [ ] Keep Supabase read-only for 30 to 60 days as a fallback, then decommission.
- [ ] Reset/rotate any passwords Ayla shared, once the accounts are DEC-controlled.

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
| `README.md` / `AGENTS.md` | Project overview and file map |
| `scripts/backup-database.sh` | One-command data export |
