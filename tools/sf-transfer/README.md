# Salesforce → Sensor Network Tracker transfer tool

Moves Salesforce records (sensor notes, communications, audits, contacts, sensors)
into the Sensor Network Tracker app, **without creating duplicates**. It's built to be
run more than once, so you can:

1. run it once,
2. keep using Salesforce and the app side by side for a while,
3. run it again just before Salesforce access ends, to catch everything logged since.

Each run only brings over what isn't in the app yet.

## Quick start: the guided program (recommended, Windows or Mac)

**You don't need any technical experience.** One program walks you through every step
with plain prompts, runs a **practice load that changes nothing**, and only loads after
you type `LOAD`. A load can be undone. Allow about an hour.

### Before you start (one time on each computer)

1. **Install Python.**
   * **Windows:** go to <https://www.python.org/downloads/>, click the yellow
     **Download** button, and run the downloaded file. Newer downloads are the
     **Python install manager**: just click through; there's no PATH checkbox, and none
     is needed. (Older installers show a checkbox **"Add python.exe to PATH"** on the
     first screen: tick it, then **Install Now**.)
     **Check it worked:** open a *new* Terminal (right-click Start → Terminal), type
     `py --version` and press Enter. You should see `Python 3.x.x`. If it offers to
     install a Python runtime, type `y` and press Enter, then check again.
   * **Mac:** same website and button; open the downloaded file and click through.
2. **Get this repository onto your computer.**
   On <https://github.com/adec-projects/sensor-network-tracker>, click the green
   **Code** button → **Download ZIP**. Open your Downloads folder, right-click the ZIP →
   **Extract All…** (Mac: double-click it). You'll get a folder named
   `sensor-network-tracker-main`. Move it somewhere easy, like Documents.
3. **Have ready:**
   * the **Salesforce export ZIP file(s)** (see *Step 1* below if you don't have them yet;
     tick the boxes to include files, so rich-text notes come through in full);
   * your **Supabase login**, and the **database password** (Supabase → Project
     Settings → Database; if nobody knows it, **Reset database password** there; nothing
     else uses it);
   * any **community that's missing from the app added in the app first**. The tool never
     creates communities.

### Run it

1. Open the `sensor-network-tracker-main` folder (the one that contains the `tools`
   folder).
2. Open a terminal **in that folder**:
   * **Windows 11:** right-click an empty spot in the folder → **Open in Terminal**.
     (Windows 10: hold **Shift**, right-click an empty spot → **Open PowerShell window
     here**.)
   * **Mac:** open **Terminal** (Cmd+Space, type Terminal), type `cd ` (with a space),
     drag the folder into the Terminal window, and press Enter.
3. Type this and press Enter:
   * **Windows:** `py tools\sf-transfer\guided_transfer.py`
   * **Mac:** `python3 tools/sf-transfer/guided_transfer.py`
4. Follow the prompts. It will:
   1. install one small database connector the first time (needs internet);
   2. ask you to **drag your Salesforce ZIP file** into the window;
   3. ask you to **paste the Supabase connection string** (Supabase → **Connect** →
      **Direct** → method **Session pooler** → copy) and then the **database password**
      (nothing shows as you type; that's normal);
   4. save a "before" copy of the app's data, for safety;
   5. if some Salesforce accounts can't be matched to a community, **open them in Excel**
      for you to decide (see *Step 3b*); save, close Excel, press Enter;
   6. open the **review page** for you to decide flagged items and check new records
      (the reviewer guide explains each choice); click **Save decisions file**;
   7. run a **PRACTICE load** and show what *would* be added. Nothing changes;
   8. ask you to type **`LOAD`** to load for real, then show what was added.
5. Check the result in the app (the program lists what to look at).

**Undo the most recent load:** open the terminal the same way and run
`py tools\sf-transfer\guided_transfer.py --undo` (Mac:
`python3 tools/sf-transfer/guided_transfer.py --undo`), then type `UNDO`. It removes
exactly what that load added. New sensors/contacts that staff have used since are kept.

**Where files go:** a folder named `sf-transfer-work` in your user folder
(`C:\Users\<you>\sf-transfer-work`, Mac `~/sf-transfer-work`). It holds contact details:
don't email it, and delete it when you're done. Keep it if you might undo or re-run; it
remembers your community decisions.

**If something goes wrong:**

| You see | Do this |
|---|---|
| `'py' is not recognized…` / `command not found` | Close the Terminal and open a **new** one (new installs only appear in new windows). Still not recognized: re-run the Python installer (older installers: choose **Modify** and tick **Add python.exe to PATH**), or install **Python 3.13** from the Microsoft Store. |
| `can't open file … guided_transfer.py` | The terminal isn't in the right folder. Close it and repeat *Run it*, step 2, from the folder that contains `tools`. |
| "Couldn't install the database connector" | Your network or computer blocked the install. Ask IT to run `py -m pip install psycopg[binary]`. |
| "The password wasn't accepted" | Reset the database password in Supabase (Project Settings → Database) and use the new one. |
| "The load stopped at statement…" | Nothing was loaded (all or nothing). Send the message shown to whoever maintains the app. |
| Excel: "can't update community-map.csv" | Close the file in Excel, then press Enter in the program. |

You can stop at any prompt by typing **Q** (or pressing Ctrl+C). Nothing is loaded until
you type `LOAD`.

---

## The files

| File | What it is |
|---|---|
| `guided_transfer.py` | **The guided program** (above). Uses `sf_transfer.py` for all the data logic. |
| `sf_transfer.py` | The tool itself, for running steps by hand (*Manual procedure* below). Python 3.8+, standard library only. |
| `review.html` | The review page (opens in any browser, works offline; also at the app's website under `/tools/sf-transfer/review.html`). |
| `README.md` | This guide. |
| `REVIEWER-GUIDE.md` | Plain-language guide for **reviewers** (anyone who knows the network). |

---

## Manual procedure (for technical staff)

Everything the guided program does, step by step, for running parts by hand, loading
the spreadsheets into another database, or troubleshooting. Mac/Linux shell commands
shown; on Windows use the guided program, or adapt the commands (the backup and
test-copy scripts are bash scripts).

**At a glance:** a Salesforce admin exports the data → run **prepare** → match any
unmatched Salesforce accounts in **community-map.csv** and run prepare again → reviewers decide flagged
items and new records in **review.html** → run **finalize** → **load** into a test copy,
check it, then load the live app.

> **OIT coordinates the review.** Reviewers are program staff, not IT, and won't know
> about this process unless OIT tells them. OIT is responsible for choosing the
> reviewer(s) with DEC, sending each one the review package and
> [`REVIEWER-GUIDE.md`](REVIEWER-GUIDE.md), walking them through it (a short call or
> screen-share is recommended the first time), answering their questions, and collecting
> their `decisions.json` files. See *Step 4*.

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
* **Creates what's missing from the app; never changes what's there.**
  * **Communities are never created.** Each Salesforce Account is matched to a
    community **already in the app**; a person confirms the ones the tool can't match
    in `community-map.csv` (*Step 3b*). If a community is missing, add it in the app first.
  * **Sensors:** every QuantAQ pod in Salesforce that isn't in the app is added with its
    SOA tag, purchase/install dates, community, and a **type** from its Salesforce status
    (Audit pod → Audit Pod, Permanent Pod → Permanent Pod, Installed → Community Pod,
    otherwise Not Assigned). The app **status is left blank** for staff to set (Salesforce
    statuses can be months old). Retired/donated pods are added as archived.
  * **Contacts:** every Salesforce contact not found in the app (matched by email, then
    name) is added.
  * New sensors and contacts appear in the review page's **New records** tab, where any
    can be skipped. Existing app records are never modified.
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

* `community-map.csv`: one row per Salesforce *Account* and the app community it
  belongs to. **If the report says accounts need a decision, do Step 3b before review.**
* `review-package.json`: the file for reviewers.
* `report.txt`: what was found, skipped, merged, and flagged.
* `app-communities.csv`: every community already in the app, with its id.

## Step 3b: Match Salesforce accounts to communities (`community-map.csv`)

Salesforce *Accounts* are a mix of communities (towns, villages, sites) and
organizations (libraries, tribal councils, schools, vendors). The tool matches most of
them to an app community automatically; a person decides the rest. **The tool never
creates communities**: if one is missing from the app, add it in the app first, make a
fresh backup (Step 2), and run *prepare* again.

1. Open `community-map.csv` (in the working folder) in Excel. Rows needing a decision are
   at the **top**, with a blank **action** and `NEEDS A DECISION` under *how_matched*.
   *records_linked* shows how many Salesforce records hang off each account, so you can
   see which matter.
2. In the **action** column, type one of:

   | action | Meaning | Also fill in |
   |---|---|---|
   | `existing` | It belongs to a community in the app | `community_id`: the app's id (e.g. `bethel`, `fbx-ncore`); every id is listed in `app-communities.csv` in the working folder |
   | `not a community` | An organization, vendor, etc. with no community | nothing |

3. You can also change rows the tool matched automatically if a match is wrong.
4. **Save as CSV** (keep the name `community-map.csv`) and run the same **prepare**
   command again. The report should now say **0** accounts need a decision.

Your decisions are kept in this file and reused on every later run (keep the working
folder, or copy `community-map.csv` into the next run's working folder). New sensors and
contacts are assigned to the community their Salesforce account maps to.

## Step 4: Review (people who know the network), coordinated by OIT

**OIT's part:**

1. With DEC, pick who reviews: someone who knows which sensors were where and which
   audits and collocations happened. More than one person can share it.
2. Send each reviewer `review-package.json` (State secure share, not email) and
   [`REVIEWER-GUIDE.md`](REVIEWER-GUIDE.md), plus a deadline.
3. **Walk them through it.** A 15-minute call or screen-share works well: open the review
   page together, load the package, and decide one or two items so they've seen each
   choice (*Import*, *Keep separate*, *Skip*) and how to save. Point out where their
   browser saves `decisions.json`.
4. Be their contact for questions, and collect every `decisions.json`.
5. Run *finalize*. If `pending-review.csv` lists anything still undecided, send it back to a
   reviewer before loading.

**The reviewer's part** (explained in plain language in the reviewer guide):

1. Open the review page in Chrome, Edge, Firefox, or Safari:
   <https://adec-projects.github.io/sensor-network-tracker/tools/sf-transfer/review.html>
   (or double-click `review.html` in this folder). It runs entirely in their browser;
   nothing is uploaded.
2. Click **Open review package…** and pick the file.
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

Several reviewers can split the work: each saves their own decisions file. Every file
arrives named `decisions.json`, so rename them as they come in (e.g.
`decisions-reviewer1.json`) and pass each one to *finalize* with its own `--decisions`
(later files win where they overlap).

## Step 5: Finalize

```
python3 tools/sf-transfer/sf_transfer.py finalize \
    --work ~/sf-transfer-work \
    --decisions ~/sf-transfer-work/decisions-reviewer1.json \
    --decisions ~/sf-transfer-work/decisions-reviewer2.json
```

By default every missing sensor and contact is added (minus any a reviewer skipped in
**New records**). Add `--only-mentioned` to add only those a transferred record refers
to.

Writes `~/sf-transfer-work/output/`:

| File | Contents |
|---|---|
| `notes.csv`, `note_tags.csv` | Notes, and the sensors/communities/contacts each is tagged to |
| `comms.csv`, `comm_tags.csv` | Communications and their tags |
| `audits.csv` | Audit records |
| `sensors_new.csv`, `contacts_new.csv` | Only sensors/contacts missing from the app (loaded first, so records can point at them) |
| `load-into-app.sql` | Loads all of the above into the Supabase app |
| `pending-review.csv` | Flagged items nobody decided yet. **Not included**; decide them and re-run finalize. |
| `skipped.csv` | Everything left out, and why |
| `SUMMARY.txt` | Counts |

The CSVs mirror the app's tables (see `docs/data-dictionary.md`), so they can be loaded
into any database, including a State-managed one. Ids are stable: the same Salesforce
record always produces the same id. Multi-value columns (`merged_sf_ids`,
`communities`) use `;` between values.

## Step 6: Load into the app

**Try it on a test copy first** (`scripts/make-test-copy.sh` makes one).

**One-time prerequisite:** the target database needs the migration
`supabase/migrations/20261106200000_audits_sf_id.sql` (already applied to the live app on
2026-11-06). To check, run this in the Supabase SQL Editor; one row back means it's there:

```
SELECT 1 FROM information_schema.columns WHERE table_name = 'audits' AND column_name = 'sf_id';
```

If no row comes back, paste the migration file's contents into the SQL Editor and click
**Run**.

Then load, with the PostgreSQL tools installed (`brew install libpq` on a Mac; Homebrew
doesn't put them on the PATH, hence the full path; on Intel Macs use
`/usr/local/opt/libpq/bin/psql`):

```
/opt/homebrew/opt/libpq/bin/psql "postgresql://postgres.<project-ref>@<pooler-host>:5432/postgres" \
     -v ON_ERROR_STOP=1 -f ~/sf-transfer-work/output/load-into-app.sql
```

(Copy the connection string from Supabase → **Connect** → **Direct** → method
*Session pooler*, and remove the `:[YOUR-PASSWORD]` part; psql asks for the database
password. It prints nothing while it works, which usually takes a minute or two, then shows the
Salesforce-imported totals. Paste the password once and wait; anything typed meanwhile
is run by the shell afterward. Make sure the whole command is pasted as **one** line.) The file runs as one transaction (all or nothing) and is
**safe to run more than once**: anything already present is left alone.

To undo a load, every transferred row has `source = 'salesforce_import'` and its
Salesforce id in `sf_id`, so it can be identified and removed.

---

## Running it again later

**With the guided program:** just run it again with the new export (keep the
`sf-transfer-work` folder so your community decisions are reused). Anything already in
the app is skipped. By hand:

1. New Salesforce export (Step 1) and a **fresh** app backup (Step 2).
2. Run **prepare** into the **same** working folder (or copy the previous
   `community-map.csv` into the new one). Anything transferred last time is now in the
   app, so it's skipped automatically. Decide any **new** unmatched accounts (Step 3b).
3. Reviewers open the new package, then click **Load earlier decisions…** and pick
   their previous `decisions.json` to carry their choices forward. Only new items need
   a decision.
4. **finalize** with all decisions files, then load.

## Tested

Built and tested in November 2026 against the spring 2026 Salesforce export and a
copy of the live app (`scripts/make-test-copy.sh`): 1,336 mass emails skipped, 976
records recognized as already transferred, the rest merged, reviewed, loaded, and checked
in the app (merged notes on every tagged sensor, audits in sensors' *Audits* sections).
Loading the same file twice added nothing.

Creating new sensors and contacts (*New records*) and the account decisions in
`community-map.csv` (Step 3b) were added in November 2026 and tested on a small sample
export covering matched/unmatched accounts, an organization, new/retired pods, and
new/existing contacts. **Check the first
real run's new records carefully** in a test copy before loading the live app.

The guided program (`guided_transfer.py`) was tested in November 2026 against a real
PostgreSQL database built from `schema/current-schema.sql`: full run, practice load
(matches the real load, changes nothing), second run (adds nothing), undo (removes
exactly that load, keeps new sensors used since), cancel prompts, and a deliberate
mid-load failure (caught in the practice run; nothing changed). Windows-specific behavior
(Excel/File Explorer opening, drag-and-drop) was written for but not tested on Windows.

## Limits worth knowing

* Communications can be tagged to communities and contacts, not sensors (an app
  rule). Sensor names are written into the communication's text instead.
* Records with no community or sensor are filed under the app's *Transferred from SF -
  no community* entry, as in the June 2026 import. Matching accounts in
  `community-map.csv` (Step 3b) keeps this to a minimum.
* Only QuantAQ pods are created as individual sensors. Other brands (AQMesh,
  PurpleAir, AirSENCE) map to the app's single entry for that brand, with the specific unit
  named in the note text.
* Device-history records linked only to a sensor get no community tag unless the text
  names one. Salesforce only knows where the sensor is *now*, which may not be where it
  was when the note was written, so the tool doesn't guess.
* The "maybe already in app" check compares date (±1 day), shared tags, and text
  similarity. It catches typical double entry; a reviewer makes the final call.
