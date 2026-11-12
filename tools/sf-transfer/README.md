# Salesforce Transfer

A web page that brings **new** Salesforce records into the Sensor Network Tracker app:
sensor notes, calls/emails, audits, plus any sensors and contacts the app doesn't have yet.

* **Nothing to install.** It's one page that runs in your web browser.
* **Only shows what's new** since the last transfer, so you never re-review old records.
* **Nothing is saved until you click Approve**, and an approved record can be undone.

**Open it here:** <https://adec-projects.github.io/sensor-network-tracker/tools/sf-transfer/>

(Or, from a downloaded copy of this repository, double-click `tools/sf-transfer/index.html`.)

**The full step-by-step guide is on the page itself** (it opens automatically, and the
**📖 Step-by-step guide** button brings it back). It starts with getting the export out of
Salesforce. The short version is below.

---

## Step 1: Get the Salesforce export

Someone with Salesforce admin access does this:

1. In Salesforce, click the **gear** (top right) → **Setup**.
2. In **Quick Find**, type **Data Export** and open it → **Export Now**.
3. **Export File Encoding:** Unicode (UTF-8). Tick **Include Salesforce Files and Salesforce
   CRM Content document versions** (so rich-text notes come through in full) and **Include all
   data**. Leave images/documents/attachments and "replace carriage returns" unticked.
4. Click **Start Export**. Salesforce emails when it's ready. Download the ZIP (its name starts
   with `WE_`) from Setup → Data Export within about 48 hours. If it's split into several ZIPs,
   use the first (`_1.ZIP`).
   Salesforce allows one export every 7 days (29 on some plans).

## Step 2: Open the page and sign in

Open the page (link above) and sign in with your **normal Sensor Network Tracker login**
and your 6-digit authenticator code. You need to be an **admin**. If you're already signed
in to the app in the same browser, it skips this.

## Step 3: Choose the export

Click the box (or drag the ZIP onto it) and pick the Salesforce ZIP. It's read right there
in your browser; nothing is uploaded anywhere. A big export can take a minute.

## Step 4: Review

At the top you'll see **"Showing Salesforce records created after [date]"**. The page fills
it in and **remembers it** in the app's settings, so it's the same on any computer:

* **Same export as last time** (you're picking up where you left off): same date.
* **A newer export** (the next transfer): the day before the previous export's newest
  record, so you only see what's been added since. Records you or anyone skipped last time
  stay hidden.
* **No earlier transfer recorded:** the date of the newest Salesforce record already in
  the app.

The note next to the date says which case applies. Change it only if you need to.

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

**⚠ Possibly already in the app.** People may have typed the same thing straight into
the app while Salesforce was still in use. The page compares each record with entries
typed into the app within 3 days of it that share a sensor, community, or contact, and
have similar wording or the same type. Matches get a ⚠ box showing the app entry (date,
type, who entered it, text):

* Same thing? Click **Skip**.
* Different? Click **Approve anyway**.
* **Approve all** never includes ⚠ records; they're left for you to check one by one.
  The left list shows how many ⚠ records each community has.

It's a helper, not a guarantee: it can miss a duplicate that was worded very differently
or tagged differently, and it can flag something that isn't one.

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
* **Running it again later** with a newer export: open the page and choose the new ZIP. The
  date is set for you from the previous run (setting `sf_transfer_cutoff` in `app_settings`,
  JSON: `{cutoff, exportNewest, previous}`). Anything already in the app is always skipped,
  whatever the date.
* **Possible duplicates** (⚠): records typed into the app by hand are matched by date (±3
  days), shared sensor/community/contact, and wording (`findDuplicates` in
  `sf-transfer-core.js`). They're never included in "Approve all".
* CSVs are read as UTF-8, falling back to Windows-1252 if the export used Salesforce's default
  Western encoding.
* **No duplicates:** each saved record stores its Salesforce id (`sf_id`, plus
  `merged_sf_ids` for combined copies), and the database refuses a second copy.
* **Communities are never created.** If one is missing, add it in the app first.
* **Attachments/files** are not transferred (by decision).
* What's written: `notes` / `note_tags`, `comms` / `comm_tags`, `audits` (with
  `source = 'salesforce_import'`), and new rows in `sensors` and `contacts`. The page uses
  the signed-in admin's normal permissions, so the database's usual rules apply.
* An earlier Python-based version is kept, retired, in `archive/sf-transfer-python/`.
