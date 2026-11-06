#!/usr/bin/env python3
"""
sf_transfer.py - move Salesforce records into the Sensor Network Tracker.

Standard library only (Python 3.8+). No data is stored in this repo: you point
the tool at a Salesforce Data Export and an app backup, and it writes into a
working folder you choose (keep that folder OFF the repo; it holds contact data).

  1. prepare   Read the Salesforce export + a backup of the app, then:
                 - skip anything already in the app (June 2026 import, earlier runs)
                 - merge the per-sensor copies Salesforce needed into ONE record
                   tagged with every sensor / community / contact
                 - flag anything a person should decide (differing text, possible
                   duplicates of notes typed into the app, collocations, audits)
               Writes  <work>/review-package.json  for reviewers (open review.html)
               and     <work>/report.txt           (what happened and why).

  2. review    Reviewers open review.html in a browser, load review-package.json,
               decide the flagged items, and save decisions.json.

  3. finalize  Apply decisions.json and write <work>/output/:
                 CSV files shaped like the app's tables (for any database), and
                 load-into-app.sql (re-runnable; never creates duplicates).

See README.md for the full walkthrough.
"""
import argparse
import collections
import csv
import datetime as dt
import difflib
import html
import io
import json
import os
import re
import sys
import uuid
import zipfile

TOOL_VERSION = "1.0"
SOURCE_TAG = "salesforce_import"
# Fixed namespace so the same Salesforce record always gets the same app id,
# run after run. That is what makes re-running safe.
ID_NAMESPACE = uuid.UUID("5f0c9a1e-6a3b-4c1e-9a55-3d2f1b7e0c11")

csv.field_size_limit(min(sys.maxsize, 2**31 - 1))


def stable_uuid(*parts):
    return str(uuid.uuid5(ID_NAMESPACE, "|".join(parts)))


def norm(s):
    """Lower-case, single-spaced, trimmed."""
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def log(msg=""):
    print(msg, flush=True)


# =============================================================================
# 1. Reading the Salesforce Data Export
# =============================================================================
# Objects we use. Everything else in the export is ignored.
SF_OBJECTS = {"Account", "Contact", "Asset", "Task", "Event", "TaskRelation",
              "EventRelation", "User", "ContentVersion", "ContentDocumentLink"}
SF_ID = re.compile(r"^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$")


class SalesforceExport:
    """One or more Data Export ZIPs (or unzipped folders), merged."""

    def __init__(self, paths):
        self.tables = {name: {} for name in SF_OBJECTS}   # name -> {Id: row}
        self.file_bodies = {}                              # ContentVersion Id -> reader()
        for p in paths:
            self._add(p)
        missing = [n for n in ("Account", "Task", "Event") if not self.tables[n]]
        if missing:
            raise SystemExit(
                "ERROR: the export is missing " + ", ".join(m + ".csv" for m in missing) +
                ". Make sure you pointed at the Salesforce Data Export ZIP file(s) and that\n"
                "'Include all data' was ticked when the export was requested.")

    def rows(self, name):
        return list(self.tables[name].values())

    def _add(self, path):
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                for n in names:
                    full = os.path.join(root, n)
                    self._member(n, lambda full=full: open(full, "rb").read())
        elif zipfile.is_zipfile(path):
            z = zipfile.ZipFile(path)
            for info in z.infolist():
                if not info.is_dir():
                    self._member(os.path.basename(info.filename),
                                 lambda z=z, info=info: z.read(info))
        else:
            raise SystemExit("ERROR: not a folder or ZIP file: " + path)

    def _member(self, base, reader):
        stem, ext = os.path.splitext(base)
        if ext.lower() == ".csv" and stem in SF_OBJECTS:
            text = reader().decode("utf-8-sig", errors="replace")
            for row in csv.DictReader(io.StringIO(text)):
                rid = row.get("Id") or row.get("ID") or ""
                if rid:
                    self.tables[stem][rid] = row
        elif SF_ID.match(stem) and stem.startswith("068"):
            # A file body from "Include Salesforce Files" (named by ContentVersion Id).
            self.file_bodies[stem] = reader


# =============================================================================
# 2. Reading the app backup (output of scripts/backup-database.sh)
# =============================================================================
APP_TABLES = {"communities", "sensors", "contacts", "notes", "note_tags",
              "comms", "comm_tags", "audits"}
_COPY_ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "\\": "\\"}


def _copy_unescape(v):
    if v == "\\N":
        return None
    if "\\" not in v:
        return v
    out, i = [], 0
    while i < len(v):
        c = v[i]
        if c == "\\" and i + 1 < len(v):
            n = v[i + 1]
            if n in _COPY_ESC:
                out.append(_COPY_ESC[n]); i += 2; continue
            m = re.match(r"[0-7]{1,3}", v[i + 1:])
            if m:
                out.append(chr(int(m.group(0), 8))); i += 1 + len(m.group(0)); continue
            out.append(n); i += 2; continue
        out.append(c); i += 1
    return "".join(out)


def _pg_array(v):
    """Parse a simple Postgres text[] literal like {a,"b c"} into a list."""
    if not v or v in ("{}",):
        return []
    inner = v[1:-1] if v.startswith("{") and v.endswith("}") else v
    return [x.strip('"') for x in next(csv.reader([inner], skipinitialspace=True))] if inner else []


def read_app_backup(folder):
    path = os.path.join(folder, "data.sql") if os.path.isdir(folder) else folder
    if not os.path.exists(path):
        raise SystemExit("ERROR: no data.sql found at " + path +
                         "\nRun ./scripts/backup-database.sh first and point --app-backup at its folder.")
    tables = {t: [] for t in APP_TABLES}
    cur = cols = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("COPY "):
                name = line.split()[1].replace('"', "").split(".")[-1]
                cur = name if name in APP_TABLES else None
                cols = line[line.index("(") + 1:line.index(")")].replace('"', "").split(", ")
                continue
            if cur is None:
                continue
            if line.startswith("\\."):
                cur = None
                continue
            vals = [_copy_unescape(x) for x in line.rstrip("\n").split("\t")]
            tables[cur].append(dict(zip(cols, vals)))
    if not tables["notes"] and not tables["communities"]:
        raise SystemExit("ERROR: " + path + " doesn't look like an app backup (no notes/communities).")
    return tables


# =============================================================================
# 3. Matching Salesforce things to app communities, sensors, contacts
# =============================================================================
# Site names that appear in note text. Only used if that community id exists in
# the app. (pattern, app community id)
SITE_ALIASES = [
    (r"\bncore\b", "fbx-ncore"),
    (r"\bfloyd\s+dryden\b", "jnu-floyd-dryden"),
    (r"\bfd\b(?=.*\b(?:site|reg|regulatory|juneau|jnu)\b)", "jnu-floyd-dryden"),
    (r"\b5th\s+st(?:reet)?\b", "jnu-5th-street"),
    (r"\bgarden\b", "anc-garden"),
    (r"\bfbx\s+lab\b|\bfairbanks\s+lab\b", "fbx-lab"),
    (r"\banc\s+lab\b|\banchorage\s+lab\b", "anc-lab"),
    (r"\bjnu\s+lab\b|\bjuneau\s+lab\b", "jnu-lab"),
]
# Salesforce account names that are vendors/companies, not communities.
NON_COMMUNITY_ACCOUNTS = {"quantaq", "tsi", "at&t", "alascom", "aqmesh", "purpleair", "airsence"}
# Account-name words that don't identify a place.
ORG_WORDS = set("""village traditional council tribal tribe native association corporation
school elementary city borough center health district community company services
department office island high middle public consortium regional area library senior
brewing tower station site inc llc the of and
alaska alaskan yukon kuskokwim interior north south east west peninsula university
national park state federal united""".split())


def _words(s):
    return [w for w in re.split(r"[^a-z0-9]+", norm(s)) if w]


class Matcher:
    def __init__(self, sf, app, community_map_rows):
        self.sf, self.app = sf, app
        # --- communities
        self.comm_ids = {r["id"] for r in app["communities"]}
        self.comm_name = {r["id"]: norm(r["name"]) for r in app["communities"]}
        self.comm_by_name = {}
        for r in app["communities"]:
            self.comm_by_name.setdefault(norm(r["name"]), r["id"])
        self.site_aliases = [(re.compile(p, re.I), cid) for p, cid in SITE_ALIASES if cid in self.comm_ids]
        self.accounts = sf.tables["Account"]
        self.account_map = {}          # sf account id -> (community id or "", method)
        overrides = {r["sf_account_id"]: (r.get("community_id") or "").strip()
                     for r in community_map_rows if r.get("sf_account_id")}
        for aid, a in self.accounts.items():
            if aid in overrides:
                cid = overrides[aid]
                if cid and cid not in self.comm_ids:
                    log(f"  WARNING: community-map.csv maps '{a.get('Name')}' to unknown community '{cid}' - ignored")
                    cid = ""
                self.account_map[aid] = (cid, "community-map.csv")
            else:
                self.account_map[aid] = self._auto_account(a)
        # parent-account fallback (e.g. a school account under a town account)
        for aid, (cid, how) in list(self.account_map.items()):
            if not cid and how != "community-map.csv":
                parent = self.accounts.get(aid, {}).get("ParentId") or ""
                pcid, _ = self.account_map.get(parent, ("", ""))
                if pcid:
                    self.account_map[aid] = (pcid, "parent account")
        # --- sensors
        self.app_sensors = {r["id"]: r for r in app["sensors"]}
        self.assets = sf.tables["Asset"]
        self.asset_sensor = {aid: self._asset_to_sensor(aid) for aid in self.assets}
        self.new_sensors = {}          # sensor id -> fields, for QuantAQ pods missing from the app
        for aid, sid in self.asset_sensor.items():
            if sid and sid.startswith("MOD-") and sid not in self.app_sensors and sid not in self.new_sensors:
                self.new_sensors[sid] = self._new_sensor_fields(aid, sid)
        self.known_sensors = set(self.app_sensors) | set(self.new_sensors)
        self.audit_pods = {sid for sid, r in self.app_sensors.items() if norm(r.get("type")) == "audit pod"}
        self.audit_pods |= {self.asset_sensor[aid] for aid, a in self.assets.items()
                            if norm(a.get("Status")) == "audit pod" and self.asset_sensor.get(aid)}
        # --- contacts
        self.app_contact_by_email, self.app_contact_by_name = {}, {}
        for r in app["contacts"]:
            if (r.get("email") or "").strip():
                self.app_contact_by_email.setdefault(norm(r["email"]), r["id"])
            self.app_contact_by_name.setdefault(norm(r["name"]), r["id"])
        self.sf_contacts = sf.tables["Contact"]
        self.contact_map = {}          # sf contact id -> app contact id
        self.new_contacts = {}         # app contact id -> fields
        for cid, c in self.sf_contacts.items():
            self.contact_map[cid] = self._match_contact(cid, c)
        # --- people who logged things in Salesforce
        self.users = {uid: (f"{u.get('FirstName', '')} {u.get('LastName', '')}".strip())
                      for uid, u in sf.tables["User"].items()}

    # ---- communities
    def _auto_account(self, a):
        name = (a.get("Name") or "").strip()
        name = re.sub(r"\b(?:ft|ft\.)\s", "Fort ", name, flags=re.I)   # "Ft Yukon" -> "Fort Yukon"
        n = norm(name)
        if not n:
            return ("", "no name")
        if n in NON_COMMUNITY_ACCOUNTS or any(n.startswith(v) for v in NON_COMMUNITY_ACCOUNTS):
            return ("", "vendor / not a community")
        if n in self.comm_by_name:
            return (self.comm_by_name[n], "exact name")
        for rx, cid in self.site_aliases:
            if rx.search(name):
                return (cid, "site name")
        for cname, cid in self.comm_by_name.items():
            if len(cname) >= 4 and (n.startswith(cname + " ") or n.startswith(cname + " -") or cname.startswith(n + " ")):
                return (cid, "name starts with community")
        tokens = [w for w in _words(name) if len(w) >= 5 and w not in ORG_WORDS]
        for t in tokens:
            hits = {cid for cname, cid in self.comm_by_name.items() if t in _words(cname)}
            if len(hits) == 1:
                return (hits.pop(), f"word '{t}'")
        return ("", "no match")

    def account_community(self, account_id):
        return self.account_map.get(account_id or "", ("", ""))[0]

    def text_sites(self, text):
        return {cid for rx, cid in self.site_aliases if rx.search(text or "")}

    # ---- sensors
    def _asset_to_sensor(self, aid, depth=0):
        a = self.assets.get(aid)
        if not a or depth > 3:
            return ""
        name = (a.get("Name") or "").strip()
        m = re.match(r"quantaq[\s_\-]*(x[\s_\-]*pm[\s_\-]*)?0*(\d{1,5})\b", name, re.I)
        if m:
            return ("MOD-X-PM-%05d" if m.group(1) else "MOD-%05d") % int(m.group(2))
        for brand in ("AQMesh", "PurpleAir", "AirSENCE"):
            if name.lower().startswith(brand.lower()):
                return brand if brand in self.app_sensors else ""
        # Spare parts / components (e.g. "OPC replacement") belong to their parent pod.
        parent = a.get("ParentId") or ""
        if parent and parent != aid:
            return self._asset_to_sensor(parent, depth + 1)
        return ""

    def asset_label(self, aid):
        return (self.assets.get(aid, {}).get("Name") or "").strip()

    def _new_sensor_fields(self, aid, sid):
        a = self.assets[aid]
        return {"id": sid, "soa_tag_id": (a.get("SOA_Tag_ID__c") or "").strip(),
                "type": "Not Assigned", "community_id": self.account_community(a.get("AccountId")) or "",
                "date_purchased": (a.get("PurchaseDate") or "")[:10],
                "date_installed": (a.get("InstallDate") or "")[:10],
                "details": "Added by the Salesforce transfer tool (Salesforce asset: %s)." % a.get("Name", "")}

    _SENSOR_PATTERNS = [
        # MOD-00665, Mod_665, Modulair 665, QuantAQ_X_PM_01657, MOD-X-PM-1657
        re.compile(r"\b(?:mod(?:ulair)?|quantaq)[\s_#\-]*(x[\s_\-]*pm[\s_\-]*)?0*(\d{3,5})\b", re.I),
        # pod 665, sensor #665, unit 665
        re.compile(r"\b(?:pod|sensor|unit)s?[\s_]*#?\s*()0*(\d{3,5})\b", re.I),
        # "#665"
        re.compile(r"(?<![\w/])#\s*()0*(\d{3,5})\b"),
        # "665 audited by 471", "audited by 471", "audit pod 471", "collocated with 471"
        re.compile(r"\b()0*(\d{3,5})\s+(?=audited\b)", re.I),
        re.compile(r"\b(?:audited\s+(?:by|with)|audit\s+pod|collocated\s+with|replaced\s+(?:by|with))[\s:#]*(?:mod[\s_#\-]*)?()0*(\d{3,5})\b", re.I),
    ]

    def text_sensors(self, text):
        found = set()
        for rx in self._SENSOR_PATTERNS:
            for m in rx.finditer(text or ""):
                xpm, num = m.group(1), int(m.group(2))
                tries = (["MOD-X-PM-%05d"] if xpm else []) + ["MOD-%05d", "MOD-X-PM-%05d"]
                for pat in tries:
                    sid = pat % num
                    if sid in self.known_sensors:
                        found.add(sid)
                        break
        return found

    # ---- contacts
    def _match_contact(self, cid, c):
        email = norm(c.get("Email") or c.get("Primary_Email__c"))
        name = f"{c.get('FirstName', '')} {c.get('LastName', '')}".strip()
        name = re.sub(r"[\s\-–(]*no longer a contact[)\s.]*$", "", name, flags=re.I).strip()
        if email and email in self.app_contact_by_email:
            return self.app_contact_by_email[email]
        if norm(name) in self.app_contact_by_name:
            return self.app_contact_by_name[norm(name)]
        if not name:
            return ""
        new_id = stable_uuid("contact", cid)
        comm = self.account_community(c.get("AccountId"))
        self.new_contacts[new_id] = {
            "id": new_id, "name": name, "role": (c.get("Title") or "").strip(),
            "org": (self.accounts.get(c.get("AccountId") or "", {}).get("Name") or "").strip(),
            "email": (c.get("Email") or "").strip(),
            "phone": (c.get("Phone") or c.get("MobilePhone") or "").strip(),
            "community_id": comm, "communities": [comm] if comm else [],
            "sf_contact_id": cid}
        return new_id

    def contact_name(self, app_or_new_id):
        if app_or_new_id in self.new_contacts:
            return self.new_contacts[app_or_new_id]["name"]
        for r in self.app["contacts"]:
            if r["id"] == app_or_new_id:
                return r["name"]
        return app_or_new_id


# =============================================================================
# 4. Turning Salesforce activities into app records
# =============================================================================
NO_COMMUNITY_ID = "transferred-from-sf---no-community"   # same fallback the June import used

RX = {k: re.compile(v, re.I) for k, v in {
    "blast":   r"^list email:",
    "commish": r"\bemail|e-mail|\bre:|\bfwd?:|\bcall\b|called|\bphone\b|voicemail|\bvm\b|left a message|"
               r"spoke with|talked to|\btext(?:ed)?\b|confirm|schedul|discuss",
    "audit":   r"audit",
    "audit_event": r"\d{1,2}/\d{1,2}/\d{2,4}\s*[-–]\s*\d{1,2}/\d{1,2}/\d{2,4}|audited|\baudit\s+(?:at|by|\(|#|\d)|"
                   r"(?:mod|pod|sensor)[\s_#\-]*\d*\s+audit\b",
    # "Removed from Garden for Glennallen audit", "Installed at Badger for audit":
    # a move/install done FOR an audit, not the audit itself.
    "audit_support": r"\b(?:for|as)\b[^.]*\baudit|\b(?:removed|installed|deployed|moved|shipped|returned|pulled)\b",
    "colloc":  r"colloc",
    "service": r"\brma\b|sent to quant|sent (?:for|back)|shipped|ship(?:ping)? to|calibrat|\bservic|repair|"
               r"returned from quant|doctor",
    "issue":   r"malfunction|replac|\bpump\b|\bpcb\b|\bopc\b|inlet|power cord|swap|offline|not reporting|overheat|"
               r"broke|outage|\bissue|error|fail|data gap|transmission|cellular|connect",
    "install": r"install|deploy|set up|setup|mounted",
    "move":    r"\bmoved\b|removed|relocat|taken down|takedown|pulled|transferred|returned to|received",
    "email":   r"\bemail|e-mail|\bre:|\bfwd?:",
    "phone":   r"\bcall\b|called|\bphone\b|voicemail|\bvm\b|left a message|spoke with|talked to|\btext(?:ed)?\b",
    "visit":   r"\bvisit\b|onsite|on-site|met with|\bmeeting\b",
    "maint":   r"clean|maintenance|\bsensor\b|\bgas\b|gaseous|\bpm\b|sd card|firmware|model update|health check",
}.items()}
GENERIC_SUBJECT = re.compile(r"^(call|phone call|email|e-mail|meeting|site visit|visit|voicemail|vm|text|"
                             r"follow up|follow-up|check in|check-in|note|notes|update)\W*$", re.I)


def classify(subject):
    """-> (kind, type). kind: note | comm | audit | skip"""
    s = subject or ""
    if RX["blast"].search(s):
        return ("skip", "")
    if RX["audit"].search(s):
        if RX["commish"].search(s):
            return ("comm", "Phone" if RX["phone"].search(s) else "Email")
        if RX["audit_event"].search(s) and not RX["audit_support"].search(s):
            return ("audit", "Audit")
    if RX["colloc"].search(s) and not RX["commish"].search(s):
        return ("note", "Collocation")
    if RX["service"].search(s):
        return ("note", "Service")
    if RX["issue"].search(s):
        return ("note", "Sensor Issue")
    if RX["install"].search(s):
        return ("note", "Installation")
    if RX["move"].search(s):
        return ("note", "Sensor Move")
    if RX["email"].search(s):
        return ("comm", "Email")
    if RX["phone"].search(s):
        return ("comm", "Phone")
    if RX["visit"].search(s):
        return ("comm", "Site Visit")
    if RX["maint"].search(s):
        return ("note", "Sensor Issue")
    return ("note", "General")


def html_to_text(raw):
    text = raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else (raw or "")
    text = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</li>", "\n", text)
    text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    return re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n\n", text)).strip()


def build_records(sf, m):
    """Every Salesforce activity / rich-text note -> one record dict (before merging)."""
    relations = collections.defaultdict(set)
    for r in sf.rows("TaskRelation"):
        relations[r.get("TaskId")].add(r.get("RelationId") or "")
    for r in sf.rows("EventRelation"):
        relations[r.get("EventId")].add(r.get("RelationId") or "")

    records, skipped = [], []

    def finish(rec, account_ids, asset_ids, sf_contact_ids, text):
        comms = {m.account_community(a) for a in account_ids} - {""}
        if not comms:
            for c in sf_contact_ids:
                cc = m.account_community(m.sf_contacts.get(c, {}).get("AccountId"))
                if cc:
                    comms.add(cc)
        comms |= m.text_sites(text)
        sensors = {m.asset_sensor.get(a) for a in asset_ids} - {"", None}
        sensors |= m.text_sensors(text)
        labels = sorted({m.asset_label(a) for a in asset_ids if not m.asset_sensor.get(a)} - {""})
        rec["communities"] = sorted(comms)
        rec["sensors"] = sorted(sensors)
        rec["contacts"] = sorted({m.contact_map.get(c) for c in sf_contact_ids} - {"", None})
        # Keep anything we can't tag as a link visible in the text so it isn't lost.
        stamp = list(labels)
        if rec["kind"] == "comm":
            stamp += rec["sensors"]          # comms can't be tagged to sensors in the app
        stamp = [s for s in stamp if s.lower() not in (rec["subject"] + " " + rec["body"]).lower()]
        if stamp:
            rec["body"] = ("[Sensor: %s] " % ", ".join(stamp) + rec["body"]).strip()
        records.append(rec)

    for origin in ("Task", "Event"):
        for x in sf.rows(origin):
            subject = (x.get("Subject") or "").strip()
            body = (x.get("Description") or "").strip()
            what = x.get("WhatId") or ""
            if RX["blast"].search(subject) or what.startswith("0XB"):
                skipped.append((x["Id"], "Mass 'List Email' blast (not a record of an event)"))
                continue
            if not subject and not body:
                skipped.append((x["Id"], "Empty (no subject or description)"))
                continue
            kind, typ = classify(subject or body)
            if kind == "skip":
                skipped.append((x["Id"], "Mass email"))
                continue
            rel = relations.get(x["Id"], set())
            account_ids = {x.get("AccountId") or ""} | {i for i in rel | {what} if i.startswith("001")}
            asset_ids = {i for i in rel | {what} if i.startswith("02i")}
            contact_ids = {i for i in rel | {x.get("WhoId") or ""} if i.startswith("003")}
            rec = {"sf_id": x["Id"], "origin": origin, "kind": kind, "type": typ,
                   "colloc": typ == "Collocation",
                   "date": (x.get("ActivityDate") or x.get("ActivityDateTime") or x.get("CreatedDate") or "")[:10],
                   "created": x.get("CreatedDate") or "", "subject": subject, "body": body,
                   "creator": x.get("CreatedById") or x.get("OwnerId") or "",
                   "logged_by": m.users.get(x.get("CreatedById") or x.get("OwnerId") or "", "")}
            finish(rec, account_ids, asset_ids, contact_ids, subject + " " + body)

    # Rich-text "Notes" (Salesforce stores them as files of type SNOTE).
    links = collections.defaultdict(set)
    for r in sf.rows("ContentDocumentLink"):
        links[r.get("ContentDocumentId")].add(r.get("LinkedEntityId") or "")
    for v in sf.rows("ContentVersion"):
        if (v.get("FileType") or "").upper() != "SNOTE" or v.get("IsLatest") not in ("1", "true", "True"):
            continue
        reader = sf.file_bodies.get(v["Id"])
        body = html_to_text(reader()) if reader else (v.get("TextPreview") or "").strip()
        title = (v.get("Title") or "").strip()
        if not body and not title:
            continue
        linked = links.get(v.get("ContentDocumentId"), set())
        kind, typ = classify(title)
        if kind in ("skip", "audit"):
            kind, typ = "note", "General"
        rec = {"sf_id": v.get("ContentDocumentId") or v["Id"], "origin": "Note", "kind": kind, "type": typ,
               "colloc": typ == "Collocation", "date": (v.get("CreatedDate") or "")[:10],
               "created": v.get("CreatedDate") or "", "subject": title, "body": body,
               "creator": v.get("CreatedById") or "", "logged_by": m.users.get(v.get("CreatedById") or "", ""),
               "body_is_preview": not reader}
        finish(rec, {i for i in linked if i.startswith("001")}, {i for i in linked if i.startswith("02i")},
               {i for i in linked if i.startswith("003")}, title + " " + body)
    return records, skipped


# =============================================================================
# 5. Consolidating the per-sensor copies into one record
# =============================================================================
_SENSOR_REF = re.compile(r"\b(?:mod(?:ulair)?|quantaq|aqmesh|purpleair|airsence|pod|sensor)[\s_#\-]*(?:x[\s_\-]*pm[\s_\-]*)?\d+\b|\[sensor:[^\]]*\]", re.I)


def _body_key(b):
    """Body text with sensor ids removed, so 'MOD-665 swapped' == 'MOD-471 swapped'."""
    return norm(_SENSOR_REF.sub("", b or ""))


def _date(s):
    try:
        return dt.date.fromisoformat((s or "")[:10])
    except ValueError:
        return None


_DATE_RANGE = re.compile(r"(\d{1,2})/(\d{1,2})/(\d{2,4})\s*[-–]\s*(\d{1,2})/(\d{1,2})/(\d{2,4})")


def _parse_range(text):
    m = _DATE_RANGE.search(text or "")
    if not m:
        return None, None
    def mk(mo, d, y):
        y = int(y); y = y + 2000 if y < 100 else y
        try:
            return dt.date(y, int(mo), int(d)).isoformat()
        except ValueError:
            return None
    return mk(*m.group(1, 2, 3)), mk(*m.group(4, 5, 6))


def make_entry(members, m, reasons=None):
    members = sorted(members, key=lambda r: (r["date"], r["created"], r["sf_id"]))
    first = members[0]
    bodies = []
    for r in members:
        if r["body"] and _body_key(r["body"]) not in [_body_key(b) for _, b in bodies]:
            label = ", ".join(r["sensors"]) or ", ".join(m.comm_name.get(c, c) for c in r["communities"])
            bodies.append((label, r["body"]))
    if len(bodies) <= 1:
        info = bodies[0][1] if bodies else ""
    else:   # differing texts: keep them all, labelled, for the reviewer to tidy
        info = "\n\n".join(("[%s] " % lbl if lbl else "") + b for lbl, b in bodies)
    union = lambda k: sorted({x for r in members for x in r[k]})
    types = collections.Counter(r["type"] for r in members)
    e = {
        "id": "E-" + first["sf_id"], "kind": first["kind"], "type": types.most_common(1)[0][0],
        "date": first["date"], "text": first["subject"] or first["body"][:400], "info": info,
        "logged_by": ", ".join(sorted({r["logged_by"] for r in members if r["logged_by"]})),
        "tags": {"community": union("communities"), "sensor": union("sensors"), "contact": union("contacts")},
        "sf_ids": [r["sf_id"] for r in members],
        "members": [{"sf_id": r["sf_id"], "date": r["date"], "subject": r["subject"], "body": r["body"],
                     "logged_by": r["logged_by"], "type": r["type"],
                     "tags": {"community": r["communities"], "sensor": r["sensors"], "contact": r["contacts"]}}
                    for r in members],
        "reasons": list(reasons or []),
    }
    if e["kind"] == "comm":
        e["tags"]["sensor"] = []                # stamped into the text instead (see build_records)
    if e["kind"] == "audit":
        e["audit"] = audit_fields(e, members, m)
    return e


def audit_fields(e, members, m):
    text = " ".join(r["subject"] + " " + r["body"] for r in members)
    start, end = _parse_range(text)
    sensors = e["tags"]["sensor"]
    audit_pod = ""
    by = re.search(r"audited\s+(?:by|with)[\s:#]*(?:mod[\s_#\-]*)?0*(\d{3,5})", text, re.I)
    if by:
        hits = [s for s in sensors if s.endswith("%05d" % int(by.group(1)))]
        audit_pod = hits[0] if hits else ""
    if not audit_pod:
        pods = [s for s in sensors if s in m.audit_pods]
        audit_pod = pods[0] if len(pods) == 1 else ""
    others = [s for s in sensors if s != audit_pod]
    community = next(iter(e["tags"]["community"]), "")
    if not community:
        # "Audit at Glennallen (24 hour)": take the community named in the text.
        # (Only for audits, which a person always reviews.)
        named = [cid for cname, cid in m.comm_by_name.items()
                 if len(cname) >= 4 and re.search(r"\b" + re.escape(cname) + r"\b", norm(text))]
        if len(named) == 1:
            community = named[0]
    return {"start_date": start or e["date"], "end_date": end or e["date"], "audit_pod_id": audit_pod,
            "community_pod_id": others[0] if len(others) == 1 else "", "community_id": community,
            "conducted_by": e["logged_by"]}


def consolidate(records, m):
    entries = []
    groups = collections.defaultdict(list)
    for r in records:
        if r["colloc"]:
            # Collocations: everything on the same date at the same place is one event,
            # whatever the exact wording. A reviewer confirms each one.
            place = ",".join(sorted(set(r["communities"]) & {cid for _, cid in m.site_aliases})) or ",".join(r["communities"])
            groups[("colloc", r["date"], place)].append(r)
        elif GENERIC_SUBJECT.match(r["subject"] or ""):
            # "Call", "Email": separate events unless the text is identical too.
            groups[("generic", r["kind"], norm(r["subject"]), r["date"], r["creator"], _body_key(r["body"]) or r["sf_id"])].append(r)
        else:
            groups[("same", r["kind"], norm(r["subject"] or r["body"][:200]), r["date"], r["creator"])].append(r)

    for key, members in groups.items():
        if key[0] == "colloc":
            e = make_entry(members, m, [{"code": "collocation", "message":
                "Collocation: %d Salesforce record(s) on %s were combined into one note. Check the sensor list." % (len(members), key[1])}])
            # Suggest other sensors that Salesforce lists as being in the same collocation.
            e["suggested_sensors"] = collocation_peers(e, m)
            entries.append(e)
            continue
        distinct = {_body_key(r["body"]) for r in members if r["body"]}
        if len(members) > 1 and len(distinct) > 1:
            entries.append(make_entry(members, m, [{"code": "text_differs", "message":
                "%d Salesforce copies of this record have different text. Choose 'merge' (one record, edit the "
                "text) or 'keep separate'." % len(members)}]))
        else:
            entries.append(make_entry(members, m))

    # Same subject + same person within 3 days: maybe the same event logged on different days.
    by_subject = collections.defaultdict(list)
    for e in entries:
        if not GENERIC_SUBJECT.match(e["text"] or "") and e["kind"] != "audit" and "collocation" not in [r["code"] for r in e["reasons"]]:
            by_subject[(e["kind"], norm(e["text"]), e["logged_by"])].append(e)
    for es in by_subject.values():
        es.sort(key=lambda e: e["date"])
        for a, b in zip(es, es[1:]):
            da, db_ = _date(a["date"]), _date(b["date"])
            if da and db_ and 0 < (db_ - da).days <= 3:
                for x, y in ((a, b), (b, a)):
                    x["reasons"].append({"code": "same_event_nearby", "ref": y["id"], "message":
                        "Same subject logged by the same person on %s. If it's the same event, skip one "
                        "and add its sensors/communities to the other." % y["date"]})

    # Audits get logged under different titles ("Audit at Glennallen (24 hour)" /
    # "Sensor audit (24hr)"), so match them by audit pod + date instead.
    audits = sorted((e for e in entries if e["kind"] == "audit"), key=lambda e: e["audit"]["start_date"] or e["date"])
    for i, a in enumerate(audits):
        for b in audits[i + 1:]:
            da, db_ = _date(a["audit"]["start_date"] or a["date"]), _date(b["audit"]["start_date"] or b["date"])
            if not (da and db_) or (db_ - da).days > 3:
                break
            pa, pb = a["audit"]["audit_pod_id"], b["audit"]["audit_pod_id"]
            if pa and pa == pb:
                for x, y in ((a, b), (b, a)):
                    x["reasons"].append({"code": "same_event_nearby", "ref": y["id"], "message":
                        "Another Salesforce audit with the same audit pod (%s) starts %s (\"%s\"). If it's the "
                        "same audit, import one and skip the other." % (pa, y["audit"]["start_date"] or y["date"], y["text"][:60])})

    for e in entries:
        if e["kind"] == "audit":
            a = e["audit"]
            problems = [p for p, ok in (("community", a["community_id"]), ("audit pod", a["audit_pod_id"]),
                                        ("community pod", a["community_pod_id"])) if not ok]
            e["reasons"].append({"code": "audit", "message": "Becomes an audit record (shows in each sensor's "
                                 "Audits section)." + (" Please fill in: " + ", ".join(problems) + "." if problems else "")})
        if not (e["tags"]["community"] or e["tags"]["sensor"]) and NO_COMMUNITY_ID in m.comm_ids:
            e["tags"]["community"] = [NO_COMMUNITY_ID]
            e["no_community_fallback"] = True
    return entries


def collocation_peers(e, m):
    """Sensors whose Salesforce 'Collocation Date Range and Location' matches the ones in this note."""
    fields = collections.defaultdict(set)
    for aid, a in m.assets.items():
        val = norm(a.get("Collocation_Date_Range_and_Location__c"))
        sid = m.asset_sensor.get(aid)
        if val and sid:
            fields[val].add(sid)
    mine = set(e["tags"]["sensor"])
    peers = set()
    for val, sids in fields.items():
        if sids & mine:
            start, end = _parse_range(val)
            d = _date(e["date"])
            if d and start and end and _date(start) - dt.timedelta(days=3) <= d <= _date(end) + dt.timedelta(days=3):
                peers |= sids
    return sorted(peers - mine)


# =============================================================================
# 6. The sweep: what is already in the app?
# =============================================================================
def _similar(a, b):
    a, b = norm(a)[:300], norm(b)[:300]
    if not a or not b:
        return 0.0
    if a in b or b in a:
        return 1.0
    return difflib.SequenceMatcher(None, a, b).ratio()


def sweep(entries, app, m):
    """Mark entries already in the app (skip) or possibly typed into the app by hand (review)."""
    in_app = set()
    for t in ("notes", "comms", "audits"):
        for r in app[t]:
            if r.get("sf_id"):
                in_app.add(r["sf_id"])
            in_app.update(_pg_array(r.get("merged_sf_ids") or ""))
    # 15-character Salesforce ids are the first 15 of the 18-character form.
    in_app15 = {s[:15] for s in in_app}

    # App records NOT from Salesforce, indexed by date, with their tags - for the
    # "typed into both systems" check.
    def manual(table, tag_table, fk):
        tags = collections.defaultdict(set)
        for t in app[tag_table]:
            tags[t[fk]].add((t["tag_type"], t["tag_id"]))
        out = collections.defaultdict(list)
        for r in app[table]:
            if r.get("source") == SOURCE_TAG or r.get("deleted_at"):
                continue
            d = _date((r.get("date") or "")[:10])
            if d:
                out[d].append((r, tags.get(r["id"], set())))
        return out
    manual_notes = manual("notes", "note_tags", "note_id")
    manual_comms = manual("comms", "comm_tags", "comm_id")

    kept, skipped = [], []
    for e in entries:
        present = [s for s in e["sf_ids"] if s in in_app or s[:15] in in_app15]
        if present and len(present) == len(e["sf_ids"]):
            skipped.append((e, "Already in the app (transferred earlier)"))
            continue
        if present:
            e["reasons"].append({"code": "partly_in_app", "message":
                "%d of the %d Salesforce copies are already in the app. Usually: skip this." %
                (len(present), len(e["sf_ids"])), "default": "skip"})
        d = _date(e["date"])
        if d and e["kind"] in ("note", "comm"):
            pool = manual_notes if e["kind"] == "note" else manual_comms
            mine = {("community", c) for c in e["tags"]["community"]} | {("sensor", s) for s in e["tags"]["sensor"]}
            for delta in (-1, 0, 1):
                for r, tags in pool.get(d + dt.timedelta(days=delta), []):
                    their = " ".join(filter(None, [r.get("subject"), r.get("text"), r.get("additional_info")]))
                    sim = _similar(e["text"] + " " + e["info"], their)
                    if (tags & mine) and sim >= 0.45:
                        e["reasons"].append({"code": "possible_app_duplicate", "default": "skip", "message":
                            "Possibly already typed into the app on %s: \"%s\" (%d%% similar). Skip if it's the same event."
                            % ((r.get("date") or "")[:10], (their[:120] + "...") if len(their) > 120 else their, sim * 100)})
                        break
        if e["kind"] == "audit":
            a = e["audit"]
            for r in app["audits"]:
                if r.get("deleted_at"):
                    continue
                sd = _date(r.get("start_date"))
                same_pod = a["community_pod_id"] and a["community_pod_id"] in (r.get("community_pod_id"), r.get("audit_pod_id"))
                same_place = a["community_id"] and a["community_id"] == r.get("community_id")
                if sd and d and abs((sd - _date(a["start_date"] or e["date"])).days) <= 10 and (same_pod or same_place):
                    e["reasons"].append({"code": "possible_app_duplicate", "default": "skip", "message":
                        "The app already has an audit at %s starting %s (pods %s / %s). Skip if it's the same audit."
                        % (r.get("community_id"), r.get("start_date"), r.get("audit_pod_id") or "?", r.get("community_pod_id") or "?")})
                    break
        kept.append(e)
    return kept, skipped


# =============================================================================
# 7. prepare: write the review package and report
# =============================================================================
def load_community_map(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def write_community_map(path, sf, m):
    rows = []
    for aid, a in sorted(sf.tables["Account"].items(), key=lambda kv: (kv[1].get("Name") or "").lower()):
        cid, how = m.account_map.get(aid, ("", ""))
        rows.append({"sf_account_id": aid, "sf_account_name": (a.get("Name") or "").strip(),
                     "community_id": cid, "community_name": m.comm_name.get(cid, ""), "how_matched": how})
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def cmd_prepare(args):
    os.makedirs(args.work, exist_ok=True)
    log("Reading the Salesforce export ...")
    sf = SalesforceExport(args.export)
    log("Reading the app backup ...")
    app = read_app_backup(args.app_backup)
    map_path = os.path.join(args.work, "community-map.csv")
    m = Matcher(sf, app, load_community_map(map_path))
    write_community_map(map_path, sf, m)

    log("Building records, merging copies, sweeping for duplicates ...")
    records, skipped_raw = build_records(sf, m)
    entries = consolidate(records, m)
    entries, skipped_entries = sweep(entries, app, m)
    for e in entries:
        e["status"] = "review" if e["reasons"] else "ready"
        e["default_action"] = "skip" if any(r.get("default") == "skip" for r in e["reasons"]) else "import"

    contacts = [{"id": r["id"], "name": r["name"], "email": r.get("email") or ""} for r in app["contacts"]]
    contacts += [{"id": c["id"], "name": c["name"], "email": c["email"], "new": True} for c in m.new_contacts.values()]
    package = {
        "tool_version": TOOL_VERSION,
        "created": dt.datetime.now().isoformat(timespec="seconds"),
        "lookups": {
            "communities": sorted(({"id": r["id"], "name": norm(r["name"]).title() if "\n" in (r["name"] or "") else r["name"]}
                                   for r in app["communities"]), key=lambda c: c["name"].lower()),
            "sensors": sorted(m.known_sensors),
            "contacts": sorted(contacts, key=lambda c: c["name"].lower()),
            "note_types": ["General", "Sensor Issue", "Installation", "Sensor Move", "Service", "Collocation", "Audit"],
            "comm_types": ["Phone", "Email", "Site Visit"],
        },
        "new_sensors": list(m.new_sensors.values()),
        "new_contacts": list(m.new_contacts.values()),
        "entries": entries,
        "skipped": [{"sf_id": s, "reason": why} for s, why in skipped_raw] +
                   [{"sf_id": e["sf_ids"][0], "sf_ids": e["sf_ids"], "text": e["text"], "date": e["date"], "reason": why}
                    for e, why in skipped_entries],
    }
    with open(os.path.join(args.work, "review-package.json"), "w", encoding="utf-8") as fh:
        json.dump(package, fh, ensure_ascii=False)
    report = write_report(args.work, package, records, m)
    log("")
    log(report)
    log("Next: give %s to the reviewers (secure share, not email)." % os.path.join(args.work, "review-package.json"))
    log("They open tools/sf-transfer/review.html, decide the flagged items, and send back decisions.json.")


def write_report(work, pkg, records, m):
    E = pkg["entries"]
    reasons = collections.Counter(r["code"] for e in E for r in e["reasons"])
    lines = [
        "SALESFORCE TRANSFER - PREPARE REPORT  (%s, tool v%s)" % (pkg["created"], pkg["tool_version"]),
        "=" * 70,
        "Salesforce records read (after skipping mass emails): %d" % len(records),
        "After merging per-sensor copies:                      %d" % (len(E) + sum(1 for s in pkg["skipped"] if "sf_ids" in s)),
        "",
        "SKIPPED (not transferred):",
    ]
    for why, n in collections.Counter(s["reason"] for s in pkg["skipped"]).most_common():
        lines.append("  %5d  %s" % (n, why))
    lines += ["", "TO TRANSFER: %d" % len(E)]
    for k, n in collections.Counter(e["kind"] for e in E).most_common():
        lines.append("  %5d  %s" % (n, {"note": "notes", "comm": "communications", "audit": "audits"}[k]))
    lines.append("  %5d  of these merge 2+ Salesforce copies into one" % sum(1 for e in E if len(e["sf_ids"]) > 1))
    lines += ["", "READY (no decision needed): %d" % sum(1 for e in E if e["status"] == "ready"),
              "NEED A REVIEWER'S DECISION:  %d" % sum(1 for e in E if e["status"] == "review")]
    labels = {"text_differs": "copies with different text (merge or keep separate?)",
              "collocation": "collocations (check which sensors belong)",
              "audit": "audits (confirm pods / community / dates)",
              "same_event_nearby": "same subject a few days apart (same event?)",
              "possible_app_duplicate": "possibly already typed into the app",
              "partly_in_app": "partly transferred before"}
    for code, n in reasons.most_common():
        lines.append("  %5d  %s" % (n, labels.get(code, code)))
    lines += ["", "ALSO ADDED: %d new sensors, %d new contacts (only ones missing from the app)."
              % (len(pkg["new_sensors"]), len(pkg["new_contacts"])),
              "Records with no community or sensor go under 'Transferred from SF - no community': %d"
              % sum(1 for e in E if e.get("no_community_fallback"))]
    unmatched = [(a.get("Name") or "") for aid, a in m.accounts.items() if not m.account_map.get(aid, ("", ""))[0]]
    lines += ["", "Salesforce accounts with no app community: %d  (fix in community-map.csv, then re-run prepare)"
              % len(unmatched)]
    previews = sum(1 for r in records if r.get("body_is_preview"))
    if previews:
        lines += ["", "WARNING: %d rich-text notes only had Salesforce's short preview text, because the export"
                  " has no file contents. Re-request the export with 'Include Salesforce Files' ticked." % previews]
    text = "\n".join(lines)
    with open(os.path.join(work, "report.txt"), "w", encoding="utf-8") as fh:
        fh.write(text + "\n")
    return text


# =============================================================================
# 8. finalize: apply decisions, write spreadsheets + load-into-app.sql
# =============================================================================
def _sql(v):
    """SQL literal. None -> NULL; "" stays an empty string (the app's default for text)."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (list, tuple)):
        return "ARRAY[%s]::text[]" % ",".join(_sql(x) for x in v) if v else "'{}'::text[]"
    return "'" + str(v).replace("'", "''") + "'"


def _ref(v):
    """A link to another table (community, sensor): blank means no link (NULL)."""
    return _sql(v or None)


def _ts(date):
    # The app stores event dates as Alaska calendar dates at midnight (see the June import).
    return (date + " 00:00:00+00") if date else None


def apply_decisions(pkg, decisions):
    """-> (final entries, pending entries, skipped-by-reviewer entries)"""
    final, pending, skipped = [], [], []
    for e in pkg["entries"]:
        d = decisions.get(e["id"])
        if d is None:
            if e["status"] == "review":
                pending.append(e)
            else:
                final.append(e)
            continue
        action = d.get("action", "import")
        if action == "skip":
            skipped.append(e)
            continue
        if action == "separate" and len(e["members"]) > 1:
            for mem in e["members"]:
                final.append({"id": "E-" + mem["sf_id"], "kind": e["kind"], "type": mem["type"], "date": mem["date"],
                              "text": mem["subject"] or mem["body"][:400], "info": mem["body"],
                              "logged_by": mem["logged_by"], "tags": {k: list(v) for k, v in mem["tags"].items()},
                              "sf_ids": [mem["sf_id"]], "audit": e.get("audit")})
            continue
        e = json.loads(json.dumps(e))      # copy, then apply the reviewer's edits
        for k in ("type", "date", "text", "info", "logged_by"):
            if k in d.get("edits", {}):
                e[k] = d["edits"][k]
        if "tags" in d.get("edits", {}):
            e["tags"] = {k: sorted(set(v)) for k, v in d["edits"]["tags"].items()}
        if "audit" in d.get("edits", {}) and e.get("audit"):
            e["audit"].update(d["edits"]["audit"])
        final.append(e)
    return final, pending, skipped


def cmd_finalize(args):
    pkg_path = os.path.join(args.work, "review-package.json")
    pkg = json.load(open(pkg_path, encoding="utf-8"))
    decisions = {}
    for path in args.decisions or []:
        d = json.load(open(path, encoding="utf-8"))
        decisions.update(d.get("decisions", d))       # later files win
    final, pending, rskipped = apply_decisions(pkg, decisions)
    out = os.path.join(args.work, "output")
    os.makedirs(out, exist_ok=True)

    notes, note_tags, comms, comm_tags, audits = [], [], [], [], []
    used_contacts, used_sensors = set(), set()
    for e in final:
        rid = stable_uuid(e["kind"], e["sf_ids"][0])
        common = {"id": rid, "source": SOURCE_TAG, "sf_id": e["sf_ids"][0],
                  "merged_sf_ids": ";".join(e["sf_ids"][1:]), "logged_by": e.get("logged_by") or ""}
        tags = e["tags"]
        used_contacts.update(tags.get("contact", []))
        used_sensors.update(tags.get("sensor", []))
        if e["kind"] == "note":
            notes.append(dict(common, date=e["date"], type=e["type"], text=e["text"], additional_info=e["info"]))
            for tt in ("community", "sensor", "contact"):
                note_tags += [{"note_id": rid, "tag_type": tt, "tag_id": t} for t in tags.get(tt, [])]
        elif e["kind"] == "comm":
            comms.append(dict(common, date=e["date"], comm_type=e["type"], subject=e["text"],
                              text=(e["text"] or e["info"])[:400], full_body=e["info"],
                              community_id=(tags.get("community") or [""])[0]))
            for tt in ("community", "contact"):
                comm_tags += [{"comm_id": rid, "tag_type": tt, "tag_id": t} for t in tags.get(tt, [])]
        elif e["kind"] == "audit":
            a = e.get("audit") or {}
            note_json = json.dumps([{"at": (e["date"] or "") + "T00:00", "by": e.get("logged_by") or "",
                                     "text": ((e["text"] or "") + ("\n" + e["info"] if e["info"] else "")).strip()}])
            audits.append(dict(common, community_id=a.get("community_id") or "", audit_pod_id=a.get("audit_pod_id") or "",
                               community_pod_id=a.get("community_pod_id") or "", status="Complete",
                               start_date=a.get("start_date") or e["date"], end_date=a.get("end_date") or e["date"],
                               conducted_by=a.get("conducted_by") or "", notes=note_json))
            used_sensors.update(x for x in (a.get("audit_pod_id"), a.get("community_pod_id")) if x)
    bad_audits = [a for a in audits if not a["community_id"]]
    audits = [a for a in audits if a["community_id"]]       # the app requires a community on audits
    new_contacts = [c for c in pkg["new_contacts"] if c["id"] in used_contacts or args.all_new_contacts]
    new_sensors = [s for s in pkg["new_sensors"] if s["id"] in used_sensors or args.all_new_contacts]

    def write(name, rows, fields):
        with open(os.path.join(out, name), "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            for r in rows:
                w.writerow({k: (";".join(v) if isinstance(v, list) else v) for k, v in r.items()})
    write("notes.csv", notes, ["id", "date", "type", "text", "additional_info", "source", "sf_id", "merged_sf_ids", "logged_by"])
    write("note_tags.csv", note_tags, ["note_id", "tag_type", "tag_id"])
    write("comms.csv", comms, ["id", "date", "comm_type", "subject", "text", "full_body", "community_id", "source", "sf_id", "merged_sf_ids", "logged_by"])
    write("comm_tags.csv", comm_tags, ["comm_id", "tag_type", "tag_id"])
    write("audits.csv", audits, ["id", "community_id", "audit_pod_id", "community_pod_id", "status", "start_date", "end_date", "conducted_by", "notes", "source", "sf_id", "merged_sf_ids", "logged_by"])
    write("contacts_new.csv", new_contacts, ["id", "name", "role", "org", "email", "phone", "community_id", "communities"])
    write("sensors_new.csv", new_sensors, ["id", "soa_tag_id", "type", "community_id", "date_purchased", "date_installed", "details"])
    write("pending-review.csv", [{"entry_id": e["id"], "kind": e["kind"], "date": e["date"], "text": e["text"],
                                  "why": " | ".join(r["message"] for r in e["reasons"])} for e in pending],
          ["entry_id", "kind", "date", "text", "why"])
    write("skipped.csv", [{"sf_ids": ";".join(s.get("sf_ids") or [s["sf_id"]]), "date": s.get("date", ""),
                           "text": s.get("text", ""), "reason": s["reason"]} for s in pkg["skipped"]] +
          [{"sf_ids": ";".join(e["sf_ids"]), "date": e["date"], "text": e["text"], "reason": "Skipped by reviewer"} for e in rskipped] +
          [{"sf_ids": a["sf_id"], "date": a["start_date"], "text": "", "reason": "Audit with no community (fix in review)"} for a in bad_audits],
          ["sf_ids", "date", "text", "reason"])
    write_load_sql(os.path.join(out, "load-into-app.sql"), notes, note_tags, comms, comm_tags, audits, new_contacts, new_sensors)

    summary = [
        "SALESFORCE TRANSFER - FINAL OUTPUT  (%s)" % dt.datetime.now().isoformat(timespec="seconds"),
        "=" * 70,
        "notes:         %5d  (+%d tags)" % (len(notes), len(note_tags)),
        "comms:         %5d  (+%d tags)" % (len(comms), len(comm_tags)),
        "audits:        %5d" % len(audits),
        "new contacts:  %5d" % len(new_contacts),
        "new sensors:   %5d" % len(new_sensors),
        "skipped by reviewer:            %d" % len(rskipped),
        "STILL WAITING FOR A DECISION:   %d  (listed in pending-review.csv; NOT included)" % len(pending),
        "audits left out (no community): %d" % len(bad_audits),
        "",
        "Files in %s:" % out,
        "  *.csv               one per app table (load into any database)",
        "  load-into-app.sql   loads everything into the Supabase app; safe to run more than once",
    ]
    with open(os.path.join(out, "SUMMARY.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(summary) + "\n")
    log("\n".join(summary))


def write_load_sql(path, notes, note_tags, comms, comm_tags, audits, contacts, sensors):
    """One transaction. Every insert checks first, so running it twice (or after a
    previous run) never creates duplicates."""
    L = ["-- Generated by tools/sf-transfer/sf_transfer.py on %s" % dt.datetime.now().isoformat(timespec="seconds"),
         "-- Loads Salesforce records into the Sensor Network Tracker. Safe to run more than once:",
         "-- anything already present (same id, or same Salesforce id) is left alone.",
         "-- Requires migration 20261106200000_audits_sf_id.sql.",
         "BEGIN;", ""]
    for s in sensors:
        L.append("INSERT INTO public.sensors (id, soa_tag_id, type, community_id, date_purchased, date_installed, details) "
                 "VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (id) DO NOTHING;" % tuple(
                     _sql(s.get(k) or "") if k in ("soa_tag_id", "date_purchased", "date_installed", "details") else _ref(s.get(k))
                     for k in ("id", "soa_tag_id", "type", "community_id", "date_purchased", "date_installed", "details")))
    for c in contacts:
        L.append("INSERT INTO public.contacts (id, name, role, org, email, phone, community_id, communities) "
                 "SELECT %s,%s,%s,%s,%s,%s,%s,%s WHERE NOT EXISTS (SELECT 1 FROM public.contacts WHERE id = %s"
                 " OR (%s <> '' AND lower(email) = lower(%s)));" % (
                     _sql(c["id"]), _sql(c["name"]), _sql(c["role"] or ""), _sql(c["org"] or ""), _sql(c["email"] or ""),
                     _sql(c["phone"] or ""), _ref(c["community_id"]), _sql(c["communities"]), _sql(c["id"]),
                     _sql(c["email"] or ""), _sql(c["email"] or "")))
    not_loaded = lambda tbl, r: ("NOT EXISTS (SELECT 1 FROM public.%s WHERE id = %s OR sf_id = ANY(%s) OR merged_sf_ids && %s)"
                                 % (tbl, _sql(r["id"]), _sql(_ids(r)), _sql(_ids(r))))
    for n in notes:
        L.append("INSERT INTO public.notes (id, date, type, text, additional_info, source, sf_id, merged_sf_ids, logged_by) "
                 "SELECT %s,%s,%s,%s,%s,%s,%s,%s,%s WHERE %s;" % (
                     _sql(n["id"]), _ref(_ts(n["date"])), _sql(n["type"]), _sql(n["text"] or ""), _sql(n["additional_info"] or ""),
                     _sql(SOURCE_TAG), _sql(n["sf_id"]), _sql(_merged(n)), _sql(n["logged_by"] or ""), not_loaded("notes", n)))
    for c in comms:
        L.append("INSERT INTO public.comms (id, date, comm_type, subject, text, full_body, community_id, source, sf_id, merged_sf_ids, logged_by) "
                 "SELECT %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s WHERE %s;" % (
                     _sql(c["id"]), _ref(_ts(c["date"])), _sql(c["comm_type"]), _sql(c["subject"] or ""), _sql(c["text"] or ""),
                     _sql(c["full_body"] or ""), _ref(c["community_id"]), _sql(SOURCE_TAG), _sql(c["sf_id"]), _sql(_merged(c)),
                     _sql(c["logged_by"] or ""), not_loaded("comms", c)))
    for a in audits:
        L.append("INSERT INTO public.audits (id, community_id, audit_pod_id, community_pod_id, status, start_date, end_date, conducted_by, notes, source, sf_id, merged_sf_ids) "
                 "SELECT %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s WHERE %s;" % (
                     _sql(a["id"]), _sql(a["community_id"]), _sql(a["audit_pod_id"] or ""), _sql(a["community_pod_id"] or ""), _sql(a["status"]),
                     _sql(a["start_date"]), _sql(a["end_date"]), _sql(a["conducted_by"] or ""), _sql(a["notes"]),
                     _sql(SOURCE_TAG), _sql(a["sf_id"]), _sql(_merged(a)), not_loaded("audits", a)))
    # Tags: only for records inserted by THIS run's ids, and never twice.
    for t in note_tags:
        L.append("INSERT INTO public.note_tags (note_id, tag_type, tag_id) SELECT %s,%s,%s WHERE EXISTS (SELECT 1 FROM public.notes WHERE id = %s) "
                 "AND NOT EXISTS (SELECT 1 FROM public.note_tags WHERE note_id = %s AND tag_type = %s AND tag_id = %s);" % (
                     _sql(t["note_id"]), _sql(t["tag_type"]), _sql(t["tag_id"]), _sql(t["note_id"]),
                     _sql(t["note_id"]), _sql(t["tag_type"]), _sql(t["tag_id"])))
    for t in comm_tags:
        L.append("INSERT INTO public.comm_tags (comm_id, tag_type, tag_id) SELECT %s,%s,%s WHERE EXISTS (SELECT 1 FROM public.comms WHERE id = %s) "
                 "AND NOT EXISTS (SELECT 1 FROM public.comm_tags WHERE comm_id = %s AND tag_type = %s AND tag_id = %s);" % (
                     _sql(t["comm_id"]), _sql(t["tag_type"]), _sql(t["tag_id"]), _sql(t["comm_id"]),
                     _sql(t["comm_id"]), _sql(t["tag_type"]), _sql(t["tag_id"])))
    L += ["", "COMMIT;", "",
          "-- Check: Salesforce-imported totals now in the app",
          "SELECT 'notes' AS t, count(*) FROM public.notes WHERE source = '%s' UNION ALL "
          "SELECT 'comms', count(*) FROM public.comms WHERE source = '%s' UNION ALL "
          "SELECT 'audits', count(*) FROM public.audits WHERE source = '%s';" % (SOURCE_TAG, SOURCE_TAG, SOURCE_TAG)]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L) + "\n")


def _ids(r):
    return [r["sf_id"]] + _merged(r)


def _merged(r):
    return [x for x in (r.get("merged_sf_ids") or "").split(";") if x]


# =============================================================================
# 9. Command line
# =============================================================================
def main(argv=None):
    p = argparse.ArgumentParser(description="Move Salesforce records into the Sensor Network Tracker. See README.md.")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("prepare", help="read the export + app backup; write the review package")
    a.add_argument("--export", action="append", required=True,
                   help="Salesforce Data Export ZIP (or unzipped folder). Repeat for multi-part exports.")
    a.add_argument("--app-backup", required=True, help="folder made by scripts/backup-database.sh (has data.sql)")
    a.add_argument("--work", required=True, help="working folder for output (keep it OUT of the repo)")
    b = sub.add_parser("finalize", help="apply reviewer decisions; write spreadsheets + load-into-app.sql")
    b.add_argument("--work", required=True, help="the same working folder used for prepare")
    b.add_argument("--decisions", action="append", help="decisions.json from review.html (repeat to combine several)")
    b.add_argument("--all-new-contacts", action="store_true",
                   help="also add Salesforce contacts/sensors that no transferred record mentions")
    args = p.parse_args(argv)
    if os.path.abspath(args.work).startswith(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) and \
            os.path.exists(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), ".git")) and \
            not os.path.abspath(args.work).startswith(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "sf-export")):
        log("NOTE: your --work folder is inside the repo. Make sure it's git-ignored (it contains contact details).")
    {"prepare": cmd_prepare, "finalize": cmd_finalize}[args.cmd](args)


if __name__ == "__main__":
    main()
