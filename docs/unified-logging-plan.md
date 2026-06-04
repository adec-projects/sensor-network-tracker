# Unified Logging Plan — one "New Log" entry point

## Problem
Logging the same real-world action can be done 3+ ways, so different people log
the same thing differently:
- Communities → Comms tab: **Log Call / Log Email / Log Site Visit / Other…** → `comms`
- Communities → History tab: **+ Add Note** → `notes`
- Sensor → Device History: **+ Add Note** → `notes`
- Contact page: **+ Log Communication** → `comms`

"Site Visit" is both a comm *type* and a note "Site Work" action; sensor work
can be a note, a comm, or a ticket. Too many doors to the same room.

## Goal
**One `+ New Log` button** on community, sensor, and contact pages → one modal.
The user says *what happened* and tags *who/what was involved*; the app routes it
to the right table. Same path for everyone, every time.

## Decisions (confirmed)
- **One modal, type chips** (not auto-detect, no extra shortcuts).
- **Keep History and Communications as separate viewing tabs** — only *creation*
  is unified. No data migration; `comms` and `notes` tables unchanged.
- **Service tickets stay separate** (RMA / FedEx / repair lifecycle). "Sensor
  work" in New Log is a quick note; a log may optionally link to an open ticket.

## The modal (`modal-new-log`)
1. **What happened?** — type chips:
   - Communication → **Call · Email · Site visit · Meeting · Text/other**
   - Note / work → **Note · Sensor work · Troubleshooting · Status change · Move sensor**
2. **Type-specific bits** appear only when relevant:
   - Status change → the status toggle list
   - Move sensor → destination-community picker
   - Sensor work / Troubleshooting → optional "link to audit / ticket"
3. **When** — datetime (defaults to now).
4. **Details** — textarea with `@`-mention contacts inline.
5. **Involved** — three cross-tag chip fields, pre-filled from context:
   - Sensors · Communities · Contacts

## Routing (invisible to the user)
| Chosen type | Saved as | Appears in |
|---|---|---|
| Call / Email / Site visit / Meeting / Text | `comm` (`comm_type`) | Communications tab |
| Note / Sensor work / Troubleshooting / Status change / Move | `note` (`type` + actions) | History tab |

Cross-tags write to `comm_tags` / `note_tags` exactly as today, so existing
views, search, and cross-tag visibility keep working unchanged.

## Smart pre-fill (by launch context)
- From a **sensor** page → that sensor + its community pre-tagged; default type "Sensor work".
- From a **community** page → that community pre-tagged; default type "Call".
- From a **contact** page → that contact + their community pre-tagged; default type "Call".
All pre-fills are removable chips.

## What changes / what's preserved
- **Removed buttons:** Log Call, Log Email, Log Site Visit, Other…, + Add Note
  (community), + Add Note (sensor), + Log Communication (contact) → all become a
  single **+ New Log** on each page.
- **Preserved:** both viewing tabs, the timelines, search, all data, service
  tickets, auto-generated movement/status notes, the `@`-mention and tag-chip
  components (reused), and the underlying `saveComm` / `saveNote` insert logic
  (reused under the hood — New Log just gathers fields and calls them).

## Implementation steps
1. Add `modal-new-log` to `index.html` (type chips + conditional sub-fields +
   date + details + 3 tag-chip containers), reusing existing chip/mention CSS.
2. `openNewLog(ctx)` — `ctx = {kind:'community'|'sensor'|'contact', id}`; sets the
   default type and pre-fills the matching chip.
3. Chip selection toggles the sub-field zones.
4. `saveNewLog()` — branch on type → reuse the existing comm/note save paths
   (including status-change / move actions) with the gathered cross-tags.
5. Swap the page buttons to `+ New Log`. Leave the old modals/functions in place
   initially (unlinked) so nothing breaks; remove them once New Log is verified.

## Rollout
Pilot on the **community page** first (highest-traffic, all types reachable),
verify, then point the sensor and contact buttons at the same modal. Backward
compatible throughout — no schema change, no data touched.
