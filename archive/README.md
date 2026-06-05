# Archive

One-shot tools from the initial Salesforce migration. Kept for reference;
not served by GitHub Pages as part of the app, not linked from anywhere
in `index.html`.

| File | Purpose |
|---|---|
| `sf-contact-migrator.html` | Salesforce contacts → `contacts` table |
| `sensor-data-importer.html` | Sensor SOA tags + purchase dates |
| `sensor-location-importer.html` | Sensor locations + historical collocations |
| `install-date-importer.html` | Sensor install dates |
| `audit-importer.html` | Bulk historical audit Excel sheets → `audits` (the everyday version of this is the in-app "Upload Audit from Excel") |
| `sf-importer.html` | Salesforce comms/notes activity history → `comms`/`notes`, reviewed community-by-community |

These write directly to the **live** Supabase database and are not everyday
tools — they live here so the day-to-day app surface stays simple. Open them
by URL (`…/archive/<file>`) only when running a migration/backfill.

If the repo ever needs to stop bundling these in a GitHub Pages deploy,
they can be safely deleted — the Salesforce source data they consumed is
no longer authoritative.
