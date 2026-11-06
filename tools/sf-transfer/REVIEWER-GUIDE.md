# Reviewing the Salesforce transfer: a guide for reviewers

**For:** anyone who knows the sensor network well: which sensors were where, and
which audits and collocations happened.
**Time:** about 1 to 2 hours, and you can stop and come back anytime.
**No technical skills, logins, or installs needed.**

> **OIT will contact you** to set this up. They'll send you the file you need, walk you
> through the review page the first time, and answer questions along the way. This guide
> is your reference for what they show you.

## What's going on

Salesforce records (sensor notes, calls, emails, audits) are being copied into the
Sensor Network Tracker app. Most of them copy over automatically. A computer can't
judge a few dozen of them, so it asks a person who knows the network. That's you.

Two common examples:

* Salesforce needed a **separate copy of each note for every sensor** so it showed up
  under each one ("CO Model Update" was logged 38 times, once per pod). The app can tag
  one note to many sensors, so the tool combines those copies into **one** note. When
  the copies don't say exactly the same thing, you decide whether they're really one
  event.
* Some events may have been **typed into both Salesforce and the app** while both were
  in use. You decide whether it's the same thing (skip it) or different (bring it over).

## What you need

1. A computer with **Chrome, Edge, Firefox, or Safari**.
2. A file called **`review-package.json`**, which OIT sends you by secure file share.
3. Your knowledge of the network: which sensors were where, and which audits and
   collocations happened.

> **Privacy:** the file contains contact names, emails, and phone numbers. Keep it on
> your State computer, don't email it, and delete it when the transfer is finished.

## Steps

1. **Open the review page:**
   <https://adec-projects.github.io/sensor-network-tracker/tools/sf-transfer/review.html>
   (Nothing is uploaded. The page works entirely inside your browser, on your
   computer.)
2. Click **Open review package…** and choose the `review-package.json` file.
3. You'll see **Needs a decision**. Work through those items. For each one:
   * Fix anything that's wrong: the text, details, type, date, and the tagged
     **communities, sensors, and contacts**. (Click **×** to remove a tag; type in
     the box to add one and pick from the list.)
   * Then choose one:
     * **Import** brings it over as shown.
     * **Keep separate** (only on combined items) brings each original Salesforce copy
       over on its own.
     * **Skip** leaves it out (for example, it's already in the app).
4. Your choices **save automatically** in this browser. You can close the page and come
   back; just open the same package file again.
5. When the counter at the top says everything is decided, click **Save decisions
   file**. It saves `decisions.json` (check your Downloads folder; some browsers save it
   next to the page instead).
6. Send `decisions.json` back to OIT, by secure share.

Items marked **Ready** will be brought over as shown. You don't need to look at them,
but you can change or skip any of them.

## What each flag means, and how to decide

| Flag | What it means | Usually… |
|---|---|---|
| **Audit** | Becomes an audit record, shown in each sensor's *Audits* section in the app. | Check the **community**, **audit pod**, **community pod**, and **dates**, and fill in blanks. A community is required. The Excel results can be attached in the app later. |
| **Collocation** | Salesforce notes about a collocation on the same date and place, combined into one note. | Check which sensors were in it. Dashed **+ MOD-…** chips are sensors Salesforce lists as being in the same collocation. Click any that belong. |
| **Copies differ** | Copies of one event have different text. | Click **Show the original Salesforce copies**. If it was one event, **Import as one** (tidy the Details text if you like). If they're really different events, **Keep separate**. |
| **Same event?** | The same subject by the same person a few days apart, or two audits with the same audit pod within 3 days. | If it's one event, **Skip** one and add its sensors/communities to the other. Otherwise import both. |
| **Maybe already in app** | Something very similar was typed into the app by hand on the same date. The message quotes it. | If it's the same thing, **Skip**. If it's different, **Import**. |
| **Partly in app** | Some copies were brought over in an earlier transfer. | Usually **Skip**. |

## Splitting the work

More than one person can share the review. Use the filter buttons at the top to divide
it by type (for example, one person takes *Audit* and *Collocation*, another takes the
rest). Each person saves and sends their own `decisions.json`; the tool combines them.

## Questions

Ask your OIT contact (the person who sent you the package). If something in the app
looks wrong after the transfer, tell OIT: every transferred record is marked as coming
from Salesforce, so it can be found and fixed.
