/*
 * sf-transfer-core.js - reads a Salesforce Data Export and turns it into review
 * cards for the Salesforce Transfer page (index.html in this folder).
 *
 * No server, no Python: runs in the browser. (Also loadable in Node for tests.)
 *
 *   SFCore.readExport(arrayBuffer, JSZip, Papa)  -> Promise<export>
 *   SFCore.analyze(export, app, {cutoff})        -> {cards, newSensors, newContacts, ...}
 *
 * "app" is what's already in the Sensor Network Tracker:
 *   {communities:[{id,name,parent_id}], sensors:[{id,type}], contacts:[{id,name,email}],
 *    inAppIds:Set(Salesforce ids already transferred, incl. merged ones)}
 */
(function (root) {
  "use strict";

  const OBJECTS = ["Account", "Contact", "Asset", "Task", "Event", "TaskRelation", "EventRelation",
                   "User", "ContentVersion", "ContentDocumentLink"];

  // ------------------------------------------------------------------ reading the ZIP
  // Salesforce exports are UTF-8 if you choose it, otherwise ISO-8859-1 (Western).
  // Try UTF-8 strictly; if the bytes aren't valid UTF-8, read them as Windows-1252.
  function decodeCsv(bytes) {
    try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
    catch (e) { return new TextDecoder("windows-1252").decode(bytes); }
  }

  async function readExport(buf, JSZip, Papa) {
    const zip = await JSZip.loadAsync(buf);
    const tables = {}; OBJECTS.forEach(o => tables[o] = []);
    const fileEntries = {};                                    // ContentVersion Id -> zip entry
    const jobs = [];
    zip.forEach((path, entry) => {
      if (entry.dir) return;
      const base = path.split("/").pop();
      const dot = base.lastIndexOf(".");
      const stem = dot > 0 ? base.slice(0, dot) : base;
      const ext = dot > 0 ? base.slice(dot + 1).toLowerCase() : "";
      const obj = OBJECTS.find(o => o.toLowerCase() === stem.toLowerCase());
      if (ext === "csv" && obj) {
        jobs.push(entry.async("uint8array").then(decodeCsv).then(text => {
          const res = Papa.parse(text.replace(/^﻿/, ""), { header: true, skipEmptyLines: true });
          tables[obj] = tables[obj].concat(res.data.filter(r => r.Id));
        }));
      } else if (/^068[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$/.test(stem)) {
        fileEntries[stem] = entry;                             // a file body (rich-text notes)
      }
    });
    await Promise.all(jobs);
    const missing = ["Account", "Task", "Event"].filter(o => !tables[o].length);
    return { tables, fileEntries, missing };
  }

  // ------------------------------------------------------------------ helpers
  const norm = s => String(s || "").trim().toLowerCase().replace(/\s+/g, " ");
  const words = s => norm(s).split(/[^a-z0-9]+/).filter(Boolean);
  const day = s => String(s || "").slice(0, 10);
  const pad5 = n => String(n).padStart(5, "0");

  const SITE_ALIASES = [
    [/\bncore\b/i, "fbx-ncore"], [/\bfloyd\s+dryden\b/i, "jnu-floyd-dryden"],
    [/\b5th\s+st(reet)?\b/i, "jnu-5th-street"], [/\bgarden\b/i, "anc-garden"],
    [/\bfbx\s+lab\b|\bfairbanks\s+lab\b/i, "fbx-lab"], [/\banc\s+lab\b|\banchorage\s+lab\b/i, "anc-lab"],
    [/\bjnu\s+lab\b|\bjuneau\s+lab\b/i, "jnu-lab"],
  ];
  const VENDORS = ["quantaq", "tsi", "at&t", "alascom", "aqmesh", "purpleair", "airsence"];
  const ORG_WORDS = new Set(("village traditional council tribal tribe native association corporation school " +
    "elementary city borough center health district community company services department office island high " +
    "middle public consortium regional area library senior brewing tower station site inc llc the of and alaska " +
    "alaskan yukon kuskokwim interior north south east west peninsula university national park state federal united").split(" "));

  const RX = {
    blast: /^list email:/i,
    commish: /\bemail|e-mail|\bre:|\bfwd?:|\bcall\b|called|\bphone\b|voicemail|\bvm\b|left a message|spoke with|talked to|\btext(ed)?\b|confirm|schedul|discuss/i,
    audit: /audit/i,
    auditEvent: /\d{1,2}\/\d{1,2}\/\d{2,4}\s*[-–]\s*\d{1,2}\/\d{1,2}\/\d{2,4}|audited|\baudit\s+(at|by|\(|#|\d)|(mod|pod|sensor)[\s_#\-]*\d*\s+audit\b/i,
    auditSupport: /\b(for|as)\b[^.]*\baudit|\b(removed|installed|deployed|moved|shipped|returned|pulled)\b/i,
    colloc: /colloc/i,
    service: /\brma\b|sent to quant|sent (for|back)|shipped|ship(ping)? to|calibrat|\bservic|repair|returned from quant|doctor/i,
    issue: /malfunction|replac|\bpump\b|\bpcb\b|\bopc\b|inlet|power cord|swap|offline|not reporting|overheat|broke|outage|\bissue|error|fail|data gap|transmission|cellular|connect/i,
    install: /install|deploy|set up|setup|mounted/i,
    move: /\bmoved\b|removed|relocat|taken down|takedown|pulled|transferred|returned to|received/i,
    email: /\bemail|e-mail|\bre:|\bfwd?:/i,
    phone: /\bcall\b|called|\bphone\b|voicemail|\bvm\b|left a message|spoke with|talked to|\btext(ed)?\b/i,
    visit: /\bvisit\b|onsite|on-site|met with|\bmeeting\b/i,
    maint: /clean|maintenance|\bsensor\b|\bgas\b|gaseous|\bpm\b|sd card|firmware|model update|health check/i,
  };
  const GENERIC = /^(call|phone call|email|e-mail|meeting|site visit|visit|voicemail|vm|text|follow up|follow-up|check in|check-in|note|notes|update)\W*$/i;

  // -> [kind, type]; kind: note | comm | audit | skip
  function classify(s) {
    s = s || "";
    if (RX.blast.test(s)) return ["skip", ""];
    if (RX.audit.test(s)) {
      if (RX.commish.test(s)) return ["comm", RX.phone.test(s) ? "Phone" : "Email"];
      if (RX.auditEvent.test(s) && !RX.auditSupport.test(s)) return ["audit", "Audit"];
    }
    if (RX.colloc.test(s) && !RX.commish.test(s)) return ["note", "Collocation"];
    if (RX.service.test(s)) return ["note", "Service"];
    if (RX.issue.test(s)) return ["note", "Sensor Issue"];
    if (RX.install.test(s)) return ["note", "Installation"];
    if (RX.move.test(s)) return ["note", "Sensor Move"];
    if (RX.email.test(s)) return ["comm", "Email"];
    if (RX.phone.test(s)) return ["comm", "Phone"];
    if (RX.visit.test(s)) return ["comm", "Site Visit"];
    if (RX.maint.test(s)) return ["note", "Sensor Issue"];
    return ["note", "General"];
  }

  const SENSOR_RX = [
    /\b(?:mod(?:ulair)?|quantaq)[\s_#\-]*(x[\s_\-]*pm[\s_\-]*)?0*(\d{3,5})\b/gi,
    /\b(?:pod|sensor|unit)s?[\s_]*#?\s*()0*(\d{3,5})\b/gi,
    /(?<![\w/])#\s*()0*(\d{3,5})\b/g,
    /\b()0*(\d{3,5})\s+(?=audited\b)/gi,
    /\b(?:audited\s+(?:by|with)|audit\s+pod|collocated\s+with|replaced\s+(?:by|with))[\s:#]*(?:mod[\s_#\-]*)?()0*(\d{3,5})\b/gi,
  ];

  function htmlToText(t) {
    return String(t || "").replace(/<br\s*\/?>|<\/p>|<\/div>|<\/li>/gi, "\n").replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/[ \t]+/g, " ").replace(/\n\s*\n+/g, "\n\n").trim();
  }

  function parseRange(text) {
    const m = /(\d{1,2})\/(\d{1,2})\/(\d{2,4})\s*[-–]\s*(\d{1,2})\/(\d{1,2})\/(\d{2,4})/.exec(text || "");
    if (!m) return [null, null];
    const mk = (mo, d, y) => { y = +y; if (y < 100) y += 2000; const dt = new Date(Date.UTC(y, mo - 1, d));
      return isNaN(dt) ? null : dt.toISOString().slice(0, 10); };
    return [mk(m[1], m[2], m[3]), mk(m[4], m[5], m[6])];
  }

  // ------------------------------------------------------------------ the analysis
  function analyze(exp, app, opts) {
    opts = opts || {};
    const T = exp.tables;
    const byId = o => Object.fromEntries(T[o].map(r => [r.Id, r]));
    const accounts = byId("Account"), assets = byId("Asset"), sfContacts = byId("Contact"), users = byId("User");
    const commIds = new Set(app.communities.map(c => c.id));
    const commName = Object.fromEntries(app.communities.map(c => [c.id, c.name]));
    const commByName = {};
    app.communities.forEach(c => { const k = norm(c.name); if (!(k in commByName)) commByName[k] = c.id; });
    const aliases = SITE_ALIASES.filter(([, id]) => commIds.has(id));
    const appSensors = new Set(app.sensors.map(s => s.id));
    const auditPods = new Set(app.sensors.filter(s => norm(s.type) === "audit pod").map(s => s.id));

    // --- accounts -> communities
    function autoAccount(a) {
      let name = String(a.Name || "").trim().replace(/\b(ft|ft\.)\s/i, "Fort ");
      const n = norm(name);
      if (!n) return "";
      if (VENDORS.some(v => n === v || n.startsWith(v))) return "";
      if (commByName[n]) return commByName[n];
      for (const [rx, id] of aliases) if (rx.test(name)) return id;
      for (const [cn, id] of Object.entries(commByName)) {
        if (cn.length >= 4 && (n.startsWith(cn + " ") || n.startsWith(cn + " -") || cn.startsWith(n + " "))) return id;
      }
      for (const t of words(name).filter(w => w.length >= 5 && !ORG_WORDS.has(w))) {
        const hits = new Set(Object.entries(commByName).filter(([cn]) => words(cn).includes(t)).map(([, id]) => id));
        if (hits.size === 1) return [...hits][0];
      }
      return "";
    }
    const accountComm = {};
    for (const [id, a] of Object.entries(accounts)) accountComm[id] = autoAccount(a);
    for (const [id, a] of Object.entries(accounts)) {          // a school under its town
      if (!accountComm[id] && a.ParentId && accountComm[a.ParentId]) accountComm[id] = accountComm[a.ParentId];
    }
    const accountOf = id => accountComm[id] || "";

    // --- assets -> sensors
    function assetSensor(id, depth) {
      const a = assets[id]; if (!a || depth > 3) return "";
      const name = String(a.Name || "").trim();
      const m = /^quantaq[\s_\-]*(x[\s_\-]*pm[\s_\-]*)?0*(\d{1,5})\b/i.exec(name);
      if (m) return (m[1] ? "MOD-X-PM-" : "MOD-") + pad5(+m[2]);
      for (const b of ["AQMesh", "PurpleAir", "AirSENCE"]) if (name.toLowerCase().startsWith(b.toLowerCase())) return appSensors.has(b) ? b : "";
      if (a.ParentId && a.ParentId !== id) return assetSensor(a.ParentId, (depth || 0) + 1);
      return "";
    }
    const assetSid = {}; for (const id of Object.keys(assets)) assetSid[id] = assetSensor(id, 0);
    const TYPE_FROM_STATUS = { "audit pod": "Audit Pod", "permanent pod": "Permanent Pod", "installed": "Community Pod",
                               "installed - needs repair": "Community Pod" };
    const newSensors = {};
    for (const [id, sid] of Object.entries(assetSid)) {
      if (!sid || !sid.startsWith("MOD-") || appSensors.has(sid) || newSensors[sid]) continue;
      const a = assets[id], st = String(a.Status || "").trim();
      newSensors[sid] = { id: sid, soa_tag_id: String(a.SOA_Tag_ID__c || "").trim(),
        type: TYPE_FROM_STATUS[norm(st)] || "Not Assigned", community_id: accountOf(a.AccountId),
        date_purchased: day(a.PurchaseDate), date_installed: day(a.InstallDate),
        active: !/^(retired|donated)/i.test(st), sf_status: st, sf_name: a.Name,
        details: "Added by the Salesforce transfer page. Salesforce asset: " + a.Name +
                 "; Salesforce status at export: " + (st || "none") + ". Set the current status in the app." };
      if (/^(audit pod)$/i.test(st)) auditPods.add(sid);
    }
    for (const [id, a] of Object.entries(assets)) if (/^audit pod$/i.test(String(a.Status || "").trim()) && assetSid[id]) auditPods.add(assetSid[id]);
    const knownSensors = new Set([...appSensors, ...Object.keys(newSensors)]);
    function textSensors(text) {
      const found = new Set();
      for (const rx of SENSOR_RX) {
        rx.lastIndex = 0; let m;
        while ((m = rx.exec(text || ""))) {
          const n = +m[2], tries = (m[1] ? ["MOD-X-PM-"] : []).concat(["MOD-", "MOD-X-PM-"]);
          for (const p of tries) { if (knownSensors.has(p + pad5(n))) { found.add(p + pad5(n)); break; } }
        }
      }
      return found;
    }
    const textSites = text => new Set(aliases.filter(([rx]) => rx.test(text || "")).map(([, id]) => id));

    // --- contacts
    const byEmail = {}, byName = {};
    app.contacts.forEach(c => { if (c.email) byEmail[norm(c.email)] = c.id; if (!(norm(c.name) in byName)) byName[norm(c.name)] = c.id; });
    const newContacts = {};
    function contactFor(cid) {
      const c = sfContacts[cid]; if (!c) return "";
      const email = norm(c.Email || c.Primary_Email__c);
      const name = (String(c.FirstName || "") + " " + String(c.LastName || "")).trim()
        .replace(/[\s\-–(]*no longer a contact[)\s.]*$/i, "").trim();
      if (email && byEmail[email]) return byEmail[email];
      if (byName[norm(name)]) return byName[norm(name)];
      if (!name) return "";
      const key = "new:" + cid;
      if (!newContacts[key]) {
        const comm = accountOf(c.AccountId);
        newContacts[key] = { key, name, role: String(c.Title || "").trim(), org: String((accounts[c.AccountId] || {}).Name || "").trim(),
          email: String(c.Email || "").trim(), phone: String(c.Phone || c.MobilePhone || "").trim(),
          community_id: comm, communities: comm ? [comm] : [], sf_contact_id: cid, created: c.CreatedDate || "" };
      }
      return key;
    }
    const userName = id => { const u = users[id]; return u ? (String(u.FirstName || "") + " " + String(u.LastName || "")).trim() : ""; };

    // --- relations (multi-contact / multi-account activities)
    const rel = {};
    T.TaskRelation.forEach(r => (rel[r.TaskId] = rel[r.TaskId] || new Set()).add(r.RelationId || ""));
    T.EventRelation.forEach(r => (rel[r.EventId] = rel[r.EventId] || new Set()).add(r.RelationId || ""));

    // --- every activity -> record
    const inApp = app.inAppIds || new Set();
    const recs = [];
    let skippedBlasts = 0;
    function addRecord(base, accountIds, assetIds, contactIds) {
      const text = base.subject + " " + base.body;
      const comms = new Set([...accountIds].map(accountOf).filter(Boolean));
      if (!comms.size) contactIds.forEach(c => { const cc = accountOf((sfContacts[c] || {}).AccountId); if (cc) comms.add(cc); });
      textSites(text).forEach(c => comms.add(c));
      const sens = new Set([...assetIds].map(a => assetSid[a]).filter(Boolean));
      textSensors(text).forEach(s => sens.add(s));
      const labels = [...assetIds].filter(a => !assetSid[a]).map(a => String((assets[a] || {}).Name || "").trim()).filter(Boolean);
      const unmatched = [...accountIds].filter(a => a && !accountOf(a) && accounts[a]).map(a => ({ id: a, name: accounts[a].Name }));
      let body = base.body;
      const stamp = labels.concat(base.kind === "comm" ? [...sens] : []).filter(s => !text.toLowerCase().includes(s.toLowerCase()));
      if (stamp.length) body = ("[Sensor: " + stamp.join(", ") + "] " + body).trim();
      recs.push(Object.assign(base, { body, communities: [...comms], sensors: [...sens],
        contacts: [...new Set(contactIds.map(contactFor).filter(Boolean))], unmatchedAccounts: unmatched }));
    }
    for (const origin of ["Task", "Event"]) {
      for (const x of T[origin]) {
        const subject = String(x.Subject || "").trim(), body = String(x.Description || "").trim(), what = x.WhatId || "";
        if (RX.blast.test(subject) || what.startsWith("0XB")) { skippedBlasts++; continue; }
        if (!subject && !body) continue;
        const [kind, type] = classify(subject || body);
        if (kind === "skip") { skippedBlasts++; continue; }
        const r = rel[x.Id] || new Set();
        const ids = [...r, what, x.WhoId || ""];
        addRecord({ sfId: x.Id, origin, kind, type, colloc: type === "Collocation",
                    date: day(x.ActivityDate || x.ActivityDateTime || x.CreatedDate), created: x.CreatedDate || "",
                    subject, body, creator: x.CreatedById || x.OwnerId || "", loggedBy: userName(x.CreatedById || x.OwnerId) },
          new Set([x.AccountId || ""].concat(ids.filter(i => i.startsWith("001")))),
          new Set(ids.filter(i => i.startsWith("02i"))), [...new Set(ids.filter(i => i.startsWith("003")))]);
      }
    }
    // Rich-text "Notes" (stored by Salesforce as files of type SNOTE)
    const links = {};
    T.ContentDocumentLink.forEach(l => (links[l.ContentDocumentId] = links[l.ContentDocumentId] || new Set()).add(l.LinkedEntityId || ""));
    const firstCreated = {};
    T.ContentVersion.forEach(v => { const d = v.ContentDocumentId; if (!firstCreated[d] || v.CreatedDate < firstCreated[d]) firstCreated[d] = v.CreatedDate; });
    for (const v of T.ContentVersion) {
      if (String(v.FileType || "").toUpperCase() !== "SNOTE" || !["1", "true", "True"].includes(String(v.IsLatest))) continue;
      const title = String(v.Title || "").trim();
      const docId = v.ContentDocumentId || v.Id;
      const linked = [...(links[v.ContentDocumentId] || [])];
      let [kind, type] = classify(title);
      if (kind === "skip" || kind === "audit") { kind = "note"; type = "General"; }
      addRecord({ sfId: docId, origin: "Note", kind, type, colloc: type === "Collocation",
                  date: day(firstCreated[v.ContentDocumentId] || v.CreatedDate), created: firstCreated[v.ContentDocumentId] || v.CreatedDate || "",
                  subject: title, body: String(v.TextPreview || "").trim(), creator: v.CreatedById || "",
                  loggedBy: userName(v.CreatedById), fileVersionId: v.Id, needsBody: !!exp.fileEntries[v.Id] },
        new Set(linked.filter(i => i.startsWith("001"))), new Set(linked.filter(i => i.startsWith("02i"))),
        linked.filter(i => i.startsWith("003")));
    }

    // --- what's new since the last transfer?
    // Default cutoff = the newest Salesforce record that's already in the app.
    let lastInApp = "", newestInExport = "";
    for (const r of recs) if (r.created > newestInExport) newestInExport = r.created;
    for (const r of recs) if ((inApp.has(r.sfId) || inApp.has(r.sfId.slice(0, 15))) && r.created > lastInApp) lastInApp = r.created;
    const cutoff = opts.cutoff != null ? opts.cutoff : (lastInApp ? lastInApp.slice(0, 10) : "");
    const isIn = id => inApp.has(id) || inApp.has(String(id).slice(0, 15));
    const counts = { total: recs.length, alreadyInApp: 0, olderThanCutoff: 0, blasts: skippedBlasts };
    const fresh = recs.filter(r => {
      if (isIn(r.sfId)) { counts.alreadyInApp++; return false; }
      if (cutoff && day(r.created) <= cutoff) { counts.olderThanCutoff++; return false; }
      return true;
    });

    // --- combine the per-sensor copies into one card
    const groups = new Map();
    const siteIds = new Set(aliases.map(([, id]) => id));
    for (const r of fresh) {
      let key;
      if (r.colloc) {
        const place = r.communities.filter(c => siteIds.has(c)).sort().join(",") || r.communities.slice().sort().join(",");
        key = ["colloc", r.date, place].join("|");
      } else if (GENERIC.test(r.subject || "")) {
        key = ["generic", r.kind, norm(r.subject), r.date, r.creator, norm(r.body) || r.sfId].join("|");
      } else {
        key = ["same", r.kind, norm(r.subject || r.body.slice(0, 200)), r.date, r.creator].join("|");
      }
      (groups.get(key) || groups.set(key, []).get(key)).push(r);
    }
    const cards = [];
    for (const members of groups.values()) {
      members.sort((a, b) => (a.date + a.created + a.sfId).localeCompare(b.date + b.created + b.sfId));
      const f = members[0];
      const bodies = [];
      for (const m of members) if (m.body && !bodies.some(b => norm(b[1]) === norm(m.body))) bodies.push([m.sensors.join(", "), m.body]);
      const union = k => [...new Set(members.flatMap(m => m[k]))];
      const card = {
        id: f.sfId, kind: f.kind, type: f.type, date: f.date, created: f.created,
        text: f.subject || f.body.slice(0, 400),
        info: bodies.length <= 1 ? (bodies[0] ? bodies[0][1] : "") : bodies.map(([l, b]) => (l ? "[" + l + "] " : "") + b).join("\n\n"),
        loggedBy: [...new Set(members.map(m => m.loggedBy).filter(Boolean))].join(", "),
        communities: union("communities"), sensors: f.kind === "comm" ? [] : union("sensors"), contacts: union("contacts"),
        sfIds: members.map(m => m.sfId), copies: members.length, textsDiffer: bodies.length > 1,
        unmatchedAccounts: [...new Map(members.flatMap(m => m.unmatchedAccounts).map(a => [a.id, a])).values()],
        needsBody: members.filter(m => m.needsBody).map(m => m.fileVersionId), colloc: f.colloc,
      };
      if (card.kind === "audit") {
        const text = members.map(m => m.subject + " " + m.body).join(" ");
        const [s, e] = parseRange(text);
        let ap = "";
        const by = /audited\s+(?:by|with)[\s:#]*(?:mod[\s_#\-]*)?0*(\d{3,5})/i.exec(text);
        if (by) ap = card.sensors.find(x => x.endsWith(pad5(+by[1]))) || "";
        if (!ap) { const pods = card.sensors.filter(x => auditPods.has(x)); ap = pods.length === 1 ? pods[0] : ""; }
        const others = card.sensors.filter(x => x !== ap);
        let comm = card.communities[0] || "";
        if (!comm) { const named = Object.entries(commByName).filter(([cn]) => cn.length >= 4 && new RegExp("\\b" + cn.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b").test(norm(text))); if (named.length === 1) comm = named[0][1]; }
        card.audit = { community_id: comm, audit_pod_id: ap, community_pod_id: others.length === 1 ? others[0] : "",
                       start_date: s || card.date, end_date: e || card.date };
      }
      cards.push(card);
    }
    cards.sort((a, b) => (a.date || "").localeCompare(b.date || ""));
    return { cards, cutoff, lastInApp, newestInExport, counts, newSensors: Object.values(newSensors),
             newContacts: Object.values(newContacts), commName, knownSensors: [...knownSensors].sort() };
  }

  async function loadBodies(exp, versionIds) {
    const out = {};
    for (const id of versionIds) {
      const e = exp.fileEntries[id];
      if (e) out[id] = htmlToText(await e.async("string"));
    }
    return out;
  }

  // ------------------------------------------------------------------ possible duplicates
  // Records people typed straight into the app have no Salesforce id, so the id check
  // can't see them. This compares each card with app entries from around the same date
  // that share a sensor/community/contact, and flags likely matches for a person to judge.
  //   entries: [{kind:'note'|'comm'|'audit', id, date:'YYYY-MM-DD', type, text, sensors[],
  //              communities[], contacts[], by, auditPod, communityPod}]
  const STOP = new Set(("the and for with was were has have had from that this are not but all out "
    + "sensor sensors pod pods mod note notes per will been they them their about into its our can").split(" "));
  const wordSet = s => new Set(String(s || "").toLowerCase().replace(/[^a-z0-9 ]+/g, " ").split(" ")
    .filter(w => w.length >= 3 && !STOP.has(w)));
  function similarity(a, b) {
    const A = wordSet(a), B = wordSet(b);
    if (!A.size || !B.size) return 0;
    let n = 0; A.forEach(w => { if (B.has(w)) n++; });
    return n / Math.min(A.size, B.size);              // share of the shorter text's words
  }
  const dayNum = d => { const t = Date.parse(String(d || "").slice(0, 10) + "T00:00:00Z"); return isNaN(t) ? null : t / 86400000; };
  function findDuplicates(cards, entries, opts) {
    const win = (opts && opts.days) || 3;
    const byDay = new Map();                            // index entries by day for speed
    for (const e of entries) { const d = dayNum(e.date); if (d == null) continue; (byDay.get(d) || byDay.set(d, []).get(d)).push(e); }
    const out = {};
    for (const c of cards) {
      const cd = dayNum(c.kind === "audit" && c.audit ? c.audit.start_date || c.date : c.date);
      if (cd == null) continue;
      const cText = (c.text || "") + " " + (c.info || "");
      const matches = [];
      for (let d = cd - win; d <= cd + win; d++) for (const e of byDay.get(d) || []) {
        const gap = Math.abs(d - cd);
        let score = 0, why = [];
        if (c.kind === "audit" || e.kind === "audit") {
          if (c.kind !== "audit" || e.kind !== "audit") continue;
          const pods = [c.audit.audit_pod_id, c.audit.community_pod_id].filter(Boolean);
          const shared = pods.filter(p => p === e.auditPod || p === e.communityPod);
          if (!shared.length && !(c.audit.community_id && c.audit.community_id === e.communities[0])) continue;
          score = 0.6 + 0.2 * shared.length; why.push(shared.length ? "same pod" : "same community");
        } else {
          const sSh = c.sensors.filter(x => (e.sensors || []).includes(x));
          const cSh = c.communities.filter(x => (e.communities || []).includes(x));
          const pSh = c.contacts.filter(x => (e.contacts || []).includes(x));
          if (!sSh.length && !cSh.length && !pSh.length) continue;
          const sim = similarity(cText, (e.text || "") + " " + (e.extra || ""));
          const sameType = e.type && c.type && e.type === c.type;
          // Flag when the wording overlaps, or when it's the same kind of entry for the
          // same sensor/contact within a day (people word things differently).
          if (sim >= 0.35) { score = sim; why.push("similar wording"); }
          else if (sameType && gap <= 1 && (sSh.length || pSh.length)) { score = 0.3; why.push("same type, same " + (sSh.length ? "sensor" : "contact")); }
          else continue;
        }
        score -= gap * 0.05;
        matches.push({ entry: e, score, gap, why: why.join(", ") });
      }
      if (matches.length) out[c.id] = matches.sort((a, b) => b.score - a.score).slice(0, 3);
    }
    return out;
  }

  const api = { readExport, analyze, loadBodies, classify, htmlToText, findDuplicates, similarity };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.SFCore = api;
})(typeof window !== "undefined" ? window : globalThis);
