# Architecture

How the ADEC Sensor Network Tracker is put together, from the browser down to the database. For an end-user oriented version, see [`user-guide.html`](user-guide.html). This doc is for developers and agents working on the code.

---

## The two pieces

```
┌───────────────────┐        ┌──────────────────────────┐
│  Browser          │        │  Supabase                │
│  (GitHub Pages)   │◀──────▶│  Postgres, Auth,         │
│  index.html       │        │  Storage, pg_cron        │
│  app.js           │        │                          │
│  supabase-client  │        │                          │
└───────────────────┘        └──────────────────────────┘
```

1. **Browser / frontend.** A single static page hosted on GitHub Pages. No build step, all vanilla JS.
2. **Supabase.** The only backend. It hosts the Postgres database, handles auth, stores uploaded files, and runs one scheduled job (a nightly trash purge via pg_cron).

QuantAQ is the sensor manufacturer (the pods are QuantAQ Modulairs), but there is no automatic API integration anymore. It was removed. Sensor issues are noticed and logged manually.

---

## Request path

A normal interaction, for example saving a sensor:

```
User clicks Save
  -> app.js calls a db.* helper (supabase-client.js)
  -> supabase-js sends the request to supabase.co
  -> an RLS policy checks the user's session against the row
  -> the row is written, the response returns to the browser
  -> app.js re-renders the view
```

Every read and write goes through a helper on the `db` object in `supabase-client.js`. There are no direct `supabase.from(...)` calls scattered through `app.js`. If you need a new query, add a `db.*` helper rather than reaching into Supabase from the UI code.

---

## Authentication

Supabase email and password auth, gated by an allowlist:

1. The `allowed_emails` table holds the emails permitted to sign up.
2. `is_email_allowed(check_email)` (called from `db.signUp`) checks against it before attempting signup.
3. A database trigger also rejects any signup whose email isn't allowed. That enforcement runs on Supabase's server, so the browser check is just a UX nicety, not the security boundary.
4. Row Level Security is enabled on every table, so without a valid session there is no data access.

The anon key committed in `supabase-client.js` is the public anon key and is safe to publish. RLS is what keeps the data private. See [`SECURITY.md`](SECURITY.md) for the full access-control model.

---

## Data model

See [`docs/data-dictionary.md`](docs/data-dictionary.md) for the table-by-table reference and [`schema/current-schema.sql`](schema/current-schema.sql) for the exact DDL. The shape at a glance:

- **`communities`** are the ~40 Alaska communities plus regulatory sites and labs, with parent/child support for sub-sites (for example NCore under Fairbanks).
- **`sensors`** are the pods. Status is a text array, so a pod can be "Online" and "PM Sensor Issue" at the same time.
- **`contacts`** are people at each community, and one contact can belong to several communities.
- **`notes`** + **`note_tags`** are the cross-tagged history. A single note can show up in the history of a sensor, a community, and a contact at once.
- **`comms`** + **`comm_tags`** are the communication log (emails, calls, site visits) using the same cross-tagging idea.
- **`audits`**, **`collocations`**, **`service_tickets`**, **`install_history`** cover field operations.
- **`community_files`** are metadata rows pointing at files in Supabase Storage.
- **`profiles`** holds user display info keyed by the auth user id; **`allowed_emails`** is the signup allowlist; **`app_settings`** is a small key/value store.

---

## Code layout

```
index.html              single-page app shell, all views and modals
styles.css              design tokens, layout, theme
app.js                  the main app (rendering, business logic)
supabase-client.js      Supabase setup and the db helper, i.e. the data layer
schema/current-schema.sql   authoritative current schema
supabase/
  config.toml
  migrations/           timestamped SQL migrations (forward-only)
```

Retired setup SQL lives in `archive/legacy-sql/` and should be treated as history. New schema changes go in `supabase/migrations/`.

---

## Conventions

- **One file per concern, mostly.** `app.js` is monolithic on purpose. Keep it that way until it is genuinely painful, and don't introduce a framework or build step without discussion.
- **All data access through `db.*`.** A feature that needs a new query gets a helper in `supabase-client.js`.
- **History is built from notes.** When something changes, the app writes a note. Preserve that pattern when adding editable fields.
- **Cross-tagging is first-class.** New entities should plug into the same `note_tags` / `comm_tags` model rather than growing parallel history tables.
- **Design rules:** navy, gold, and white only; DM Sans and JetBrains Mono; tokens in `:root`.

---

## Deployment

- Push to `main` and GitHub Pages rebuilds automatically.
- Database changes: add a new file under `supabase/migrations/` and apply it with `supabase db push` or through the Supabase SQL editor.

---

## What's deliberately not here

- **No build step, bundler, TypeScript, or framework.** Adding any of these is a large decision, not something to do incidentally.
- **No staging environment.** Local dev points at production Supabase. If that becomes a real problem, the answer is a second Supabase project, not mocks.
- **No custom backend server.** Supabase is the whole backend.
