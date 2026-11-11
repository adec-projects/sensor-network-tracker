# Salesforce Transfer

A web page that brings **new** Salesforce records into the Sensor Network Tracker app:
sensor notes, calls/emails, audits, plus any sensors and contacts the app doesn't have yet.

* **Nothing to install.** It's one page that runs in your web browser.
* **Only shows what's new** since the last transfer, so you never re-review old records.
* **Nothing is saved until you click Approve**, and an approved record can be undone.

**Open it here:** <https://adec-projects.github.io/sensor-network-tracker/tools/sf-transfer/>

(Or, from a downloaded copy of this repository, double-click `tools/sf-transfer/index.html`.)

---

## Step 1: Get the Salesforce export

Someone with Salesforce admin access does this:

1. In Salesforce, click the **gear** (top right) → **Setup**.
2. In **Quick Find**, type **Data Export** and open it → **Export Now**.
3. Tick **Include Salesforce Files and Salesforce CRM Content document versions**
   (so rich-text notes come through in full) and **Include all data**.
4. Click **Start Export**. Salesforce emails a download link when it's ready (usually a few
   hours). Download the ZIP file (its name starts with `WE_`).

## Step 2: Open the page and sign in

Open the page (link above) and sign in with your **normal Sensor Network Tracker login**
and your 6-digit authenticator code. You need to be an **admin**. If you're already signed
in to the app in the same browser, it skips this.

## Step 3: Choose the export

Click the box (or drag the ZIP onto it) and pick the Salesforce ZIP. It's read right there
in your browser; nothing is uploaded anywhere. A big export can take a minute.

## Step 4: Review

At the top you'll see **"Showing Salesforce records created after [date]"**. The page
works out that date from the last transfer and **remembers it** (in the app's settings),
so it stays the same while you work, even across days or computers. Change it only if you
need to.

Down the left side:

* **New sensors**: pods in Salesforce that aren't in the app. Check the type and
  community, then **Create** (or **Create all**). The app status is left blank for staff
  to set. Retired pods are added as archived.
* **New contacts**: people in Salesforce who aren't in the app. **Create** the ones you
  want.
* **Each community**, with how many records are left. Click one to see its records.
* **`? Account name`**: records from a Salesforce account the page couldn't match to a
  community. Pick the community at the top of that list, and it applies to all of them.

Each record is a card. Salesforce's per-sensor copies of the same event are **already
combined into one card** ("3 Salesforce copies combined"), tagged with every sensor,
community, and contact. Sensors named in the text (like "mod 665 audited by mod 471") are
already tagged. For each card:

* Fix anything that's wrong (type, date, text, tags). Use **→ Make it a note /
  communication** if it's the wrong kind.
* **Approve** saves it to the app right away. **Approve all N here** does a whole community.
* **Skip** hides it for good (remembered in this browser). Tick **show skipped** to see
  skipped ones again and **Un-skip**.
* **Undo** (on an approved card) removes it from the app again.

Audits get extra fields (community, audit pod, community pod, dates) and are saved as
audit records, so they show in each sensor's **Audits** section. The Excel results can be
attached on the audit's page in the app afterward.

You can stop anytime and come back: open the page, choose the same ZIP, and you'll see
only what's left.

## What it looks like in the app

Imported notes and communications show **"Created by [Salesforce author], SF import"**,
the same as the June 2026 transfer. New sensors say in their Details that they were added
by this page.

---

## For whoever maintains this later

* **Files:** `index.html` (the page) and `sf-transfer-core.js` (reads the export and builds
  the cards). Plain HTML/JavaScript; libraries load from public CDNs (supabase-js, JSZip,
  PapaParse). No build step.
* **Running it again later** with a newer export: open the page, choose the new ZIP, and set
  the date at the top to the date of the previous transfer (the page shows the date it
  saved last time). Anything already in the app is always skipped, whatever the date.
* **No duplicates:** each saved record stores its Salesforce id (`sf_id`, plus
  `merged_sf_ids` for combined copies), and the database refuses a second copy.
* **Communities are never created.** If one is missing, add it in the app first.
* **Attachments/files** are not transferred (by decision).
* What's written: `notes` / `note_tags`, `comms` / `comm_tags`, `audits` (with
  `source = 'salesforce_import'`), and new rows in `sensors` and `contacts`. The page uses
  the signed-in admin's normal permissions, so the database's usual rules apply.
* An earlier Python-based version is kept, retired, in `archive/sf-transfer-python/`.
