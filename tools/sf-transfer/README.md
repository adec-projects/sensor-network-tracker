# Salesforce → Sensor Network Tracker transfer tool

Moves Salesforce records (sensor notes, communications, audits, contacts, sensors)
into the Sensor Network Tracker app, **without creating duplicates**. It's built to be
run more than once, so you can:

1. run it once,
2. keep using Salesforce and the app side by side for a while,
3. run it again just before Salesforce access ends, to catch everything logged since.

Each run only brings over what isn't in the app yet.

| File | What it is |
|---|---|
| `sf_transfer.py` | The tool. Python 3.8+, **standard library only** (nothing to install). |
| `review.html` | The review page for people who know the network (opens in any browser, works offline). |
| `README.md` | This guide, for whoever **runs** the transfer (OIT). |
| `REVIEWER-GUIDE.md` | Plain-language guide for the **reviewers** (Lydia, Isaac). Send them this. |

**At a glance:** a Salesforce admin exports the data → OIT runs **prepare** → reviewers
decide the flagged items in **review.html** → OIT runs **finalize** and **loads** it.
Try it on a test copy of the app first.

> **Privacy.** The Salesforce export, the app backup, and everything the tool writes
> contain names, emails, and phone numbers. Keep them **out of this repository** and
> share them only by a State secure file share, never email. The repo contains code
> only.

---

## What it does with the data

* **Skips** mass "List Email" blasts, and anything **already in the app** (matched by
  Salesforce record id, including records merged in earlier runs and the June 2026
  import).
* **Merges per-sensor copies.** Salesforce needed one copy of an event per sensor or
  community so it showed up under each. Copies with the same subject, date, and author
  become **one** app record tagged with **every** sensor, community, and contact.
  Vague subjects like "Call" are never merged (they're usually different calls).
* **Tags from the text.** "Mod 665 audited by mod 471" logged under Bethel is tagged
  Bethel, MOD-00665, and MOD-00471. Site names (NCore, Floyd Dryden, Garden, labs)
  are tagged too.
* **Sensor moves and installs are notes only.** The tool never changes a sensor's
  current location or status.
* **Audits** ("Wrangell audit 3/4/25-3/11/25", "Mod 665 audited by 471") become
  **audit records**, so they show in each sensor's *Audits* section. Emails and calls
  *about* an audit stay communications. The Excel results can be attached to the audit
  in the app afterward.
* **Collocations** logged on the same date at the same place become one note with all
  the sensors; Salesforce's "Collocation Date Range and Location" field is used to
  suggest any sensors that were missed.
* **Adds missing contacts and sensors only.** Existing app records are never changed.
* **Asks a person** whenever it isn't sure (see *Review*).
* Attachments/files are **not** transferred (by decision). Rich-text Salesforce Notes
  *are* transferred, as notes.

---

## Step 1: Get the Salesforce export (someone with Salesforce admin access)

This is a few clicks in Salesforce; no technical knowledge needed.

1. In Salesforce, click the **gear** (top right) → **Setup**.
2. In **Quick Find** (top left), type **Data Export** and open it.
3. Click **Export Now**.
4. Tick **Include Salesforce Files and Salesforce CRM Content document versions** and
   **Include images, documents, and attachments**. (Rich-text Notes are stored as
   files; without these boxes only a short preview of each note is exported.)
5. Under *Exported Data*, tick **Include all data**.
6. Click **Start Export**. Salesforce emails you when it's ready (usually a few hours).
7. Download **every** ZIP file listed (big exports are split into several). The
   download links expire after about 48 hours.

Salesforce only allows an export every so often (weekly or monthly, depending on the
edition), so plan the final run ahead of the date Salesforce access ends.

## Step 2: Back up the app

From the repository folder:

```
./scripts/backup-database.sh
```

It asks for the app's database password (Supabase dashboard → Project Settings →
Database) and writes `handoff-backup-YYYYMMDD/`. The tool reads `data.sql` from it to
know what's already in the app. **Make a fresh backup right before each run.**

## Step 3: Prepare

Choose a working folder **outside** the repository, e.g. `~/sf-transfer-work`.

```
python3 tools/sf-transfer/sf_transfer.py prepare \
    --export ~/Downloads/WE_00D..._1.ZIP \
    --export ~/Downloads/WE_00D..._2.ZIP \
    --app-backup handoff-backup-YYYYMMDD \
    --work ~/sf-transfer-work
```

(One `--export` per ZIP file.) It prints a report (also saved as `report.txt`) and
writes:

* `review-package.json`: the file for reviewers.
* `community-map.csv`: how each Salesforce *Account* was matched to an app community.
  If one is wrong or blank, fix the `community_id` column (use an id from the app,
  e.g. `bethel`, `fbx-ncore`) and run **prepare** again. Your fixes are kept on
  every later run.

## Step 4: Review (people who know the network)

Send `review-package.json` to the reviewer(s) by secure share, together with
[`REVIEWER-GUIDE.md`](REVIEWER-GUIDE.md), which explains everything below in plain
language. They:

1. Open `review.html` from this folder in Chrome, Edge, Firefox, or Safari (double-click it,
   or use the copy on the app's website, `.../tools/sf-transfer/review.html`). It runs
   entirely in their browser; nothing is uploaded.
2. Click **Open review package** and pick the file.
3. Work through **Needs a decision**: fix text, type, date, and the tagged
   communities/sensors/contacts; then choose **Import**, **Keep separate**, or **Skip**.
   Progress is saved in the browser, so they can stop and come back.
4. Click **Save decisions file** and send `decisions.json` back. (Some browsers save it
   next to `review.html` rather than in *Downloads*. If so, move it out of the
   repository folder; it's git-ignored, but it contains contact details.)

What gets flagged:

| Flag | Meaning |
|---|---|
| Copies differ | Salesforce copies of one event have different text. Merge (and tidy the text) or keep separate. |
| Collocation | A collocation note: check which sensors belong. Suggested sensors are one click to add. |
| Audit | Confirm community, audit pod, community pod, and dates. |
| Maybe already in app | Something very similar was typed into the app by hand on the same date. Usually *Skip*. |
| Same event? | Same subject by the same person a few days apart, or two audits with the same audit pod within 3 days. |
| Partly in app | Some copies were transferred before. Usually *Skip*. |

Several reviewers can split the work: each saves their own decisions file, and you pass
all of them to *finalize* (later files win where they overlap).

## Step 5: Finalize

```
python3 tools/sf-transfer/sf_transfer.py finalize \
    --work ~/sf-transfer-work --decisions ~/Downloads/decisions.json
```

Writes `~/sf-transfer-work/output/`:

| File | Contents |
|---|---|
| `notes.csv`, `note_tags.csv` | Notes, and the sensors/communities/contacts each is tagged to |
| `comms.csv`, `comm_tags.csv` | Communications and their tags |
| `audits.csv` | Audit records |
| `contacts_new.csv`, `sensors_new.csv` | Only contacts/sensors missing from the app |
| `load-into-app.sql` | Loads all of the above into the Supabase app |
| `pending-review.csv` | Flagged items nobody decided yet. **Not included**; decide them and re-run finalize. |
| `skipped.csv` | Everything left out, and why |
| `SUMMARY.txt` | Counts |

The CSVs mirror the app's tables (see `docs/data-dictionary.md`), so they can be loaded
into any database, including a State-managed one. Ids are stable: the same Salesforce
record always produces the same id. Multi-value columns (`merged_sf_ids`,
`communities`) use `;` between values.

## Step 6: Load into the app

**Try it on a test copy first** (`scripts/make-test-copy.sh` makes one). Then, for the
live app, with the PostgreSQL tools installed (`brew install libpq` on a Mac):

```
psql "postgresql://postgres.<project-ref>@<pooler-host>:5432/postgres" \
     -v ON_ERROR_STOP=1 -f ~/sf-transfer-work/output/load-into-app.sql
```

(Copy the connection string from Supabase → **Connect** → **Direct** → method
*Session pooler*, and remove the `:[YOUR-PASSWORD]` part; psql asks for the database
password. It prints nothing while it works, which usually takes a minute or two, then shows the
Salesforce-imported totals. Paste the password once and wait; anything typed meanwhile
is run by the shell afterward. Make sure the whole command is pasted as **one** line.) The file runs as one transaction (all or nothing) and is
**safe to run more than once**: anything already present is left alone. It needs the
migration `supabase/migrations/20261106200000_audits_sf_id.sql` to have been applied.

To undo a load, every transferred row has `source = 'salesforce_import'` and its
Salesforce id in `sf_id`, so it can be identified and removed.

---

## Running it again later

1. New Salesforce export (Step 1) and a **fresh** app backup (Step 2).
2. Run **prepare** into the **same** working folder. Anything transferred last time is
   now in the app, so it's skipped automatically, as is anything already decided.
3. Reviewers open the new package. To carry their earlier choices forward, they click
   **Load earlier decisions** first. Only new items need a decision.
4. **finalize** with all decisions files, then load.

## Tested

Built and tested in November 2026 against the spring 2026 Salesforce export and a
copy of the live app (`scripts/make-test-copy.sh`): 1,336 mass emails skipped, 976
records recognized as already transferred, the rest merged, reviewed, loaded, and checked
in the app (merged notes on every tagged sensor, audits in sensors' *Audits* sections).
Loading the same file twice added nothing.

## Limits worth knowing

* Communications can be tagged to communities and contacts, not sensors (an app
  rule). Sensor names are written into the communication's text instead.
* Records with no community or sensor are filed under the app's *Transferred from SF -
  no community* entry, as in the June 2026 import.
* Device-history records linked only to a sensor get no community tag unless the text
  names one. Salesforce only knows where the sensor is *now*, which may not be where it
  was when the note was written, so the tool doesn't guess.
* The "maybe already in app" check compares date (±1 day), shared tags, and text
  similarity. It catches typical double entry; a reviewer makes the final call.
