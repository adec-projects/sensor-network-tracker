#!/usr/bin/env python3
"""
guided_transfer.py - step-by-step Salesforce -> Sensor Network Tracker transfer.

Works on Windows and Mac. Walks you through everything with plain prompts:
reading the Salesforce export, checking what's already in the app, matching
Salesforce accounts to communities, the review page, a PRACTICE load that changes
nothing, the real load, and an exact UNDO of what was loaded.

How to start it (see README.md "Quick start"): open a Terminal, type  py  and a space
(Mac: python3 and a space), drag this file into the window, and press Enter.
To undo the most recent load, do the same but add  --undo  at the end.

Uses sf_transfer.py (same folder) for all the data logic, and the "psycopg"
library to talk to the database (installed automatically the first time).
"""
import argparse
import csv
import datetime as dt
import getpass
import glob
import json
import os
import subprocess
import sys
import textwrap
import urllib.parse
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import sf_transfer as T  # noqa: E402

LIVE_REF = "uejryzioxogquflijgyf"
APP_URL = "https://adec-projects.github.io/sensor-network-tracker/"
REVIEW_URL = APP_URL + "tools/sf-transfer/review.html"
WORK = os.environ.get("SNT_TEST_WORK") or os.path.join(os.path.expanduser("~"), "sf-transfer-work")
DOWNLOADS = os.environ.get("SNT_TEST_DOWNLOADS") or os.path.join(os.path.expanduser("~"), "Downloads")
AUDITS_MIGRATION = os.path.join(REPO, "supabase", "migrations", "20261106200000_audits_sf_id.sql")
IS_WINDOWS = os.name == "nt"
# The exact command to run this program again, from any folder (shown for --undo).
RUN_CMD = '%s "%s"' % ("py" if IS_WINDOWS else "python3", os.path.abspath(__file__))


# --------------------------------------------------------------------------- helpers
def say(text=""):
    print(textwrap.dedent(text).strip("\n"))
    sys.stdout.flush()


def step(n, title):
    print("\n" + "=" * 78)
    print(" STEP %s: %s" % (n, title))
    print("=" * 78)


def ask(prompt):
    try:
        return input(prompt + " ").strip()
    except EOFError:
        return ""


def pause(prompt="Press Enter to continue (or type Q to quit)."):
    if ask("\n" + prompt).lower() in ("q", "quit", "exit"):
        say("\nStopped. Nothing else was changed. Run this program again to start over.")
        sys.exit(0)


def clean_path(s):
    """A path typed, pasted, or dragged into the window (which may add quotes)."""
    s = (s or "").strip().strip("&").strip().strip('"').strip("'").strip()
    if not IS_WINDOWS:
        s = s.replace("\\ ", " ")          # Mac Terminal escapes spaces when you drag a file in
    return os.path.expanduser(s)


def open_thing(path_or_url):
    if os.environ.get("SNT_TEST_NO_OPEN"):        # automated tests
        print("   [would open] %s" % path_or_url)
        return
    try:
        if path_or_url.startswith("http"):
            webbrowser.open(path_or_url)
        elif IS_WINDOWS:
            os.startfile(path_or_url)      # noqa: (Windows only)
        elif sys.platform == "darwin":
            subprocess.run(["open", path_or_url], check=False)
        else:
            subprocess.run(["xdg-open", path_or_url], check=False)
    except Exception:
        say("(Couldn't open it automatically. Open it yourself: %s)" % path_or_url)


def fail(msg):
    say("\n*** " + msg)
    say("\nNothing has been loaded into the app. Fix the problem above and run this program again.")
    sys.exit(1)


# --------------------------------------------------------------------------- database
def ensure_psycopg():
    try:
        import psycopg  # noqa: F401
        return
    except ImportError:
        pass
    say("""
    One-time setup: installing the database connector ("psycopg"). This takes about a minute
    and needs an internet connection...""")
    r = subprocess.run([sys.executable, "-m", "pip", "install", "--user", "--quiet", "psycopg[binary]"])
    try:
        import importlib
        import site
        importlib.invalidate_caches()
        if site.getusersitepackages() not in sys.path:
            sys.path.append(site.getusersitepackages())
        import psycopg  # noqa: F401
        say("Installed.")
    except ImportError:
        fail("Couldn't install the database connector (exit code %s). If your computer blocks this, ask IT "
             "to run:  %s -m pip install psycopg[binary]" % (r.returncode, "py" if IS_WINDOWS else "python3"))


def connect():
    """Ask for the Supabase connection string + password; return (connection, project ref)."""
    import psycopg
    test_uri = os.environ.get("SNT_TEST_DB_URI")      # developers' automated tests only
    if test_uri:
        return psycopg.connect(test_uri), "local-test"
    say("""
    Now connect to the app's database. In your web browser:
      1. Go to supabase.com and sign in. Open the Sensor Network Tracker project.
      2. Click "Connect" (top of the page). Choose the "Direct" box, then change the method
         to "Session pooler".
      3. Copy the connection string. It starts with  postgresql://postgres.  and contains
         [YOUR-PASSWORD]  (that's fine; you'll type the password separately).""")
    for attempt in range(3):
        raw = ask("\nPaste the connection string here and press Enter:")
        u = urllib.parse.urlsplit(raw.strip().strip('"'))
        if u.scheme not in ("postgres", "postgresql") or not u.hostname or not (u.username or "").startswith("postgres."):
            say("That doesn't look like the Session pooler connection string (it should start with "
                "postgresql://postgres.). Please copy it again.")
            continue
        ref = u.username.split(".", 1)[1]
        say("\nType the DATABASE password (Supabase > Project Settings > Database). Nothing will show as you "
            "type or paste; that's normal. Then press Enter.")
        pw = getpass.getpass("Database password: ")
        try:
            conn = psycopg.connect(host=u.hostname, port=u.port or 5432, dbname=(u.path or "/postgres").lstrip("/") or "postgres",
                                   user=u.username, password=pw, sslmode="require", connect_timeout=20)
            return conn, ref
        except Exception as e:
            msg = str(e).strip().splitlines()[0] if str(e).strip() else repr(e)
            if "password authentication failed" in msg:
                say("The password wasn't accepted. If you're not sure of it, reset it in Supabase: Project Settings > "
                    "Database > Reset database password. (Nothing else in the app uses it.)")
            else:
                say("Couldn't connect: " + msg)
    fail("Couldn't connect to the database after 3 tries.")


def _text(v):
    """Database value -> the text form sf_transfer.py expects (same as a backup file)."""
    if v is None:
        return None
    if isinstance(v, bool):
        return "t" if v else "f"
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(str(x) for x in v) + "}"
    if isinstance(v, dict):
        return json.dumps(v)
    return str(v)


def read_app(conn):
    tables = {}
    with conn.cursor() as cur:
        for t in sorted(T.APP_TABLES):
            cur.execute("SELECT * FROM public.%s" % t)
            cols = [c.name for c in cur.description]
            tables[t] = [{k: _text(v) for k, v in zip(cols, row)} for row in cur.fetchall()]
    conn.rollback()
    return tables


def save_snapshot(conn, folder):
    """A 'before' copy of every app table as CSV, for safety."""
    os.makedirs(folder, exist_ok=True)
    with conn.cursor() as cur:
        cur.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1")
        names = [r[0] for r in cur.fetchall()]
        for t in names:
            with open(os.path.join(folder, t + ".csv"), "wb") as fh:
                with cur.copy("COPY public.%s TO STDOUT WITH CSV HEADER" % t) as cp:
                    for chunk in cp:
                        fh.write(chunk)
    conn.rollback()
    return names


def ensure_audits_column(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM information_schema.columns WHERE table_schema='public' "
                    "AND table_name='audits' AND column_name='sf_id'")
        ok = cur.fetchone()
    conn.rollback()
    if ok:
        return
    say("\nThis database is missing one small, harmless addition the tool needs (a 'Salesforce id' column "
        "on audits). It adds columns only and changes no data.")
    if ask("Add it now? Type YES and press Enter:").upper() != "YES":
        fail("The audits column is required. Run the program again and type YES when asked.")
    sql = open(AUDITS_MIGRATION, encoding="utf-8").read().replace("NOTIFY pgrst, 'reload schema';", "")
    with conn.cursor() as cur:
        cur.execute(sql)
        cur.execute("NOTIFY pgrst, 'reload schema'")
    conn.commit()
    say("Added.")


COUNT_SQL = {
    "notes from Salesforce": "SELECT count(*) FROM public.notes WHERE source = 'salesforce_import'",
    "communications from Salesforce": "SELECT count(*) FROM public.comms WHERE source = 'salesforce_import'",
    "audits from Salesforce": "SELECT count(*) FROM public.audits WHERE source = 'salesforce_import'",
    "sensors": "SELECT count(*) FROM public.sensors",
    "contacts": "SELECT count(*) FROM public.contacts",
}
ID_TABLES = {"notes": "notes", "comms": "comms", "audits": "audits", "sensors": "sensors", "contacts": "contacts"}


def counts(cur):
    out = {}
    for k, q in COUNT_SQL.items():
        cur.execute(q)
        out[k] = cur.fetchone()[0]
    return out


def present_ids(cur, ids):
    out = {}
    for k, table in ID_TABLES.items():
        want = ids.get(k) or []
        if not want:
            out[k] = set()
            continue
        cur.execute("SELECT id::text FROM public.%s WHERE id::text = ANY(%%s)" % table, (want,))
        out[k] = {r[0] for r in cur.fetchall()}
    return out


def run_load(conn, plan, commit):
    """Run every statement in ONE transaction. Practice run: roll back at the end."""
    stmts, ids = plan["statements"], plan["ids"]
    with conn.cursor() as cur:
        before = counts(cur)
        pre = present_ids(cur, ids)
        for i, stmt in enumerate(stmts, 1):
            try:
                cur.execute(stmt)
            except Exception as e:
                conn.rollback()
                fail("The load stopped at statement %d of %d, so NOTHING was loaded (all or nothing).\n"
                     "Database message: %s\nStatement starts: %s"
                     % (i, len(stmts), str(e).strip().splitlines()[0], stmt[:160]))
            if i % 200 == 0:
                print("   ... %d of %d" % (i, len(stmts)), flush=True)
        after = counts(cur)
        post = present_ids(cur, ids)
        added = {k: sorted(post[k] - pre[k]) for k in ID_TABLES}
    if commit:
        conn.commit()
    else:
        conn.rollback()
    return before, after, added


def show_counts(before, after, verb):
    say("")
    for k in COUNT_SQL:
        d = after[k] - before[k]
        say("   %-34s %6d  ->  %6d   (%s %d)" % (k, before[k], after[k], verb, d))


# --------------------------------------------------------------------------- undo
def undo(args):
    ensure_psycopg()
    files = sorted(f for f in glob.glob(os.path.join(WORK, "undo-*.json"))
                   if any(json.load(open(f, encoding="utf-8"))["added"].values()))
    if not files:
        fail("No record of a load that added anything was found in %s, so there's nothing to undo." % WORK)
    rec = json.load(open(files[-1], encoding="utf-8"))
    added = rec["added"]
    step("UNDO", "remove what the load on %s added" % rec["loaded_at"])
    say("This will remove exactly what that load added:")
    for k in ID_TABLES:
        say("   %-10s %d" % (k, len(added.get(k) or [])))
    say("New sensors and contacts are kept if anything entered since then refers to them.")
    conn, ref = connect()
    say("\nConnected to: %s" % ("the LIVE Sensor Network Tracker app" if ref == LIVE_REF else "database '%s'" % ref))
    if ref != rec.get("project"):
        fail("This isn't the database that load went into (%s). Nothing was changed." % rec.get("project"))
    if ask("Type UNDO and press Enter to remove them (anything else cancels):") != "UNDO":
        say("Cancelled. Nothing was changed.")
        return
    kept = {}
    with conn.cursor() as cur:
        for t in ("notes", "comms", "audits"):
            if added.get(t):
                cur.execute("DELETE FROM public.%s WHERE id::text = ANY(%%s) AND source = 'salesforce_import'" % t, (added[t],))
        if added.get("sensors"):
            cur.execute("""DELETE FROM public.sensors s WHERE s.id = ANY(%s)
                           AND NOT EXISTS (SELECT 1 FROM public.note_tags t WHERE t.tag_type='sensor' AND t.tag_id = s.id)
                           AND NOT EXISTS (SELECT 1 FROM public.audits a WHERE s.id IN (a.audit_pod_id, a.community_pod_id))
                           RETURNING id""", (added["sensors"],))
            kept["sensors"] = len(added["sensors"]) - cur.rowcount
        if added.get("contacts"):
            cur.execute("""DELETE FROM public.contacts c WHERE c.id::text = ANY(%s)
                           AND NOT EXISTS (SELECT 1 FROM public.note_tags t WHERE t.tag_type='contact' AND t.tag_id = c.id::text)
                           AND NOT EXISTS (SELECT 1 FROM public.comm_tags t WHERE t.tag_type='contact' AND t.tag_id = c.id::text)
                           RETURNING id""", (added["contacts"],))
            kept["contacts"] = len(added["contacts"]) - cur.rowcount
    conn.commit()
    os.replace(files[-1], files[-1].replace("undo-", "undone-"))
    say("\nDone. The load has been removed.")
    for k, n in kept.items():
        if n:
            say("   Kept %d new %s because something entered later refers to them." % (n, k))


# --------------------------------------------------------------------------- main flow
def main():
    p = argparse.ArgumentParser(description="Guided Salesforce -> Sensor Network Tracker transfer.")
    p.add_argument("--undo", action="store_true", help="remove what the most recent load added")
    args = p.parse_args()
    if sys.version_info < (3, 8):
        fail("This needs Python 3.8 or newer (you have %s)." % sys.version.split()[0])
    if args.undo:
        return undo(args)

    step(1, "what's going to happen")
    say("""
    This program moves Salesforce records into the Sensor Network Tracker app:
    sensor notes, calls/emails, audits, plus any sensors and contacts the app is missing.
    It never changes or deletes what's already in the app, and it skips anything that was
    transferred before.

    You'll:
      - point it at your Salesforce export ZIP file(s)
      - connect it to the app's database (Supabase)
      - match any Salesforce accounts it can't place to a community (in Excel)
      - review flagged items on a web page
      - watch a PRACTICE load that changes nothing, then approve the real one

    Allow about an hour. You can stop at any prompt by typing Q; nothing is loaded until
    the very last step, and even that can be undone.

    Working files go in:  %s
    They contain contact details. Don't email them; delete the folder when you're done.""" % WORK)
    os.makedirs(WORK, exist_ok=True)
    pause()

    step(2, "one-time setup")
    ensure_psycopg()
    say("Ready.")

    step(3, "your Salesforce export")
    say("""
    Find the Salesforce export ZIP file you downloaded (usually in Downloads; its name starts
    with WE_). Drag it from File Explorer (Mac: Finder) into this window, then press Enter.
    If the export came as several ZIP files, add them one at a time. When you've added them
    all, press Enter on an empty line.""")
    exports = []
    while True:
        raw = ask("\nZIP file %d (or just Enter if done):" % (len(exports) + 1))
        if not raw:
            if exports:
                break
            say("Please add at least one ZIP file.")
            continue
        path = clean_path(raw)
        if not os.path.exists(path):
            say("Can't find that file: %s  (Try dragging it in again.)" % path)
        elif not (os.path.isdir(path) or path.lower().endswith(".zip")):
            say("That isn't a ZIP file. The Salesforce export is a .zip file.")
        else:
            exports.append(path)
            say("   added: %s" % os.path.basename(path))
    try:
        sf = T.SalesforceExport(exports)
    except SystemExit as e:
        fail(str(e))
    say("Read the export: %d activity records, %d accounts, %d sensors (assets), %d contacts."
        % (len(sf.tables["Task"]) + len(sf.tables["Event"]), len(sf.tables["Account"]),
           len(sf.tables["Asset"]), len(sf.tables["Contact"])))

    step(4, "connect to the app's database")
    conn, ref = connect()
    if ref == LIVE_REF:
        say("\nConnected to the LIVE Sensor Network Tracker database. (Nothing will be changed until the "
            "last step, and only after you confirm.)")
    else:
        say("\nConnected to database '%s'. NOTE: this is NOT the live app (a test copy?)." % ref)
    ensure_audits_column(conn)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M")
    snap = os.path.join(WORK, "app-before-" + stamp)
    say("Saving a 'before' copy of the app's data (for safety) ...")
    names = save_snapshot(conn, snap)
    say("   saved %d tables to %s" % (len(names), snap))
    app = read_app(conn)
    say("The app currently has %d sensors, %d contacts, %d notes, %d communications, %d communities."
        % (len(app["sensors"]), len(app["contacts"]), len(app["notes"]), len(app["comms"]), len(app["communities"])))

    step(5, "match Salesforce accounts to communities")
    ns = argparse.Namespace(export=exports, app_backup=None, app=app, work=WORK, guided=True)
    while True:
        try:
            T.cmd_prepare(ns)
        except SystemExit as e:
            if str(e) and str(e) != "0":
                say(str(e))
                pause("Fix that (e.g. close the file in Excel), then press Enter to try again (Q to quit).")
                continue
            raise
        pkg = json.load(open(os.path.join(WORK, "review-package.json"), encoding="utf-8"))
        und = pkg.get("undecided_accounts") or []
        if not und:
            say("\nEvery Salesforce account is matched. Good.")
            break
        say("""
        ---------------------------------------------------------------------------
        %d Salesforce account(s) couldn't be matched to an app community (listed above).
        Excel will open two files:
          - community-map.csv       the list to fill in (undecided rows are at the TOP)
          - app-communities.csv     every community in the app, with its id (for reference)

        For each row with a blank "action", type in the action column either:
          existing          and put the app's community id in the community_id column
                            (copy it from app-communities.csv), or
          not a community   if it's an organization, vendor, etc.

        Then: File > Save (if Excel asks, keep the CSV format), and CLOSE Excel.
        Tip: if a community is truly missing from the app, add it in the app first, then
        quit here (Q) and run this program again.
        ---------------------------------------------------------------------------""" % len(und))
        open_thing(os.path.join(WORK, "app-communities.csv"))
        open_thing(os.path.join(WORK, "community-map.csv"))
        r = ask("\nWhen you've saved and closed Excel, press Enter to re-check. "
                "(Type SKIP to continue anyway: records linked only to those accounts get no community.)")
        if r.lower() in ("q", "quit"):
            sys.exit(0)
        if r.lower() == "skip":
            break

    step(6, "review flagged items (web page)")
    pkg = json.load(open(os.path.join(WORK, "review-package.json"), encoding="utf-8"))
    n_review = sum(1 for e in pkg["entries"] if e["status"] == "review")
    say("""
    %d item(s) need a person's decision, and there are %d new sensor(s) and %d new contact(s)
    you can check. Your browser will open the review page, and a folder window will show
    the file to load into it.

      1. On the page, click "Open review package..." and choose  review-package.json
         (in the folder that just opened:  %s).
      2. Work through "Needs a decision". Check the "New records" tab too.
         (The page's own instructions, and REVIEWER-GUIDE.md, explain each choice.)
      3. Click "Save decisions file". It usually saves decisions.json to Downloads.""" % (
        n_review, len(pkg["new_sensors"]), len(pkg["new_contacts"]), WORK))
    open_thing(REVIEW_URL)
    open_thing(WORK)
    pkg_time = os.path.getmtime(os.path.join(WORK, "review-package.json"))
    decisions = None
    while decisions is None:
        r = ask("\nWhen you've clicked 'Save decisions file', press Enter. "
                "(Or drag the decisions file in. Type NONE to skip review: only the 'Ready' items would load.)")
        if r.lower() in ("q", "quit"):
            sys.exit(0)
        if r.upper() == "NONE":
            decisions = ""
            break
        if r:
            cand = clean_path(r)
        else:
            found = [f for f in glob.glob(os.path.join(DOWNLOADS, "decisions*.json")) +
                     glob.glob(os.path.join(REPO, "**", "decisions*.json"), recursive=True)
                     if os.path.getmtime(f) >= pkg_time - 5]
            cand = max(found, key=os.path.getmtime) if found else ""
            if not cand:
                say("Couldn't find a new decisions file in Downloads. Drag it into this window instead.")
                continue
        if not os.path.exists(cand):
            say("Can't find: %s" % cand)
            continue
        keep = os.path.join(WORK, "decisions-%s.json" % stamp)
        with open(cand, "rb") as src, open(keep, "wb") as dst:
            dst.write(src.read())
        if os.path.dirname(os.path.abspath(cand)).startswith(REPO):
            os.remove(cand)          # never leave contact data inside the repo folder
        decisions = keep
        say("   using %s (copied to the working folder)" % os.path.basename(cand))

    step(7, "build the final load")
    T.cmd_finalize(argparse.Namespace(work=WORK, decisions=[decisions] if decisions else [], only_mentioned=False))
    plan = json.load(open(os.path.join(WORK, "output", "load-statements.json"), encoding="utf-8"))
    pending = list(csv.DictReader(open(os.path.join(WORK, "output", "pending-review.csv"), encoding="utf-8")))
    if pending:
        say("\nNOTE: %d flagged item(s) weren't decided and will NOT be loaded. That's OK; they're listed in "
            "output/pending-review.csv. To include them, quit (Q), decide them on the review page, and run "
            "this program again." % len(pending))
    pause()

    step(8, "PRACTICE load (changes nothing)")
    say("Running the whole load inside the database, then cancelling it, to show what would happen ...")
    before, after, _ = run_load(conn, plan, commit=False)
    show_counts(before, after, "would add")
    say("\nThe practice load worked and was cancelled. The app has NOT been changed.")

    step(9, "the real load")
    target = "the LIVE Sensor Network Tracker app" if ref == LIVE_REF else "database '%s' (not the live app)" % ref
    say("This will add the records above to %s.\nIt can be undone afterwards with:\n   %s --undo" % (target, RUN_CMD))
    if ask("\nType LOAD and press Enter to load them (anything else stops here, nothing loaded):") != "LOAD":
        say("Stopped. Nothing was loaded.")
        return
    before, after, added = run_load(conn, plan, commit=True)
    show_counts(before, after, "added")
    if any(added.values()):
        # Exactly what THIS load added (not things that were already there), for --undo.
        rec = {"loaded_at": dt.datetime.now().isoformat(timespec="seconds"), "project": ref, "added": added}
        with open(os.path.join(WORK, "undo-%s.json" % dt.datetime.now().strftime("%Y%m%d-%H%M%S")), "w",
                  encoding="utf-8") as fh:
            json.dump(rec, fh)
    else:
        say("\nNothing new was added (everything was already in the app).")

    step(10, "check it and finish")
    say("""
    Loaded. Now check it in the app (it's opening in your browser; refresh if it was open):
      - Open a sensor you know had Salesforce notes, and look at its history.
      - Open a new sensor (see the "New records" tab you reviewed).
      - Open an audit pod and look at its Audits section.

    If something looks badly wrong, undo the whole load by running this (copy it now and
    keep it somewhere safe):
      %s --undo

    When you're satisfied:
      - Write down today's date as the "Salesforce transfer date". Anything entered only in
        Salesforce after your export date won't be in the app.
      - Keep the folder %s for now if you might re-run or undo; delete it when you're sure
        (it holds contact details).""" % (RUN_CMD, WORK))
    open_thing(APP_URL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nStopped. Nothing was loaded unless you had already typed LOAD.")
        sys.exit(1)
