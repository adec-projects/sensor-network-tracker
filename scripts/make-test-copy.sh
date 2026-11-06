#!/usr/bin/env bash
#
# make-test-copy.sh - copy the LIVE Sensor Network Tracker database into a
# separate, EMPTY Supabase "test" project, so tools (like the Salesforce
# transfer tool) can be tested without touching the live app.
#
# Copies: the app's tables, functions and rules (public schema), all app data,
# and the user logins (auth users + authenticator setups), so the same people
# can sign in to the test copy with their normal password and code.
# Does NOT copy: uploaded files, scheduled jobs, file-storage rules.
#
# The LIVE database is only READ. Only the TEST project is written to.
#
# What you need:
#   - PostgreSQL tools:  brew install libpq
#   - The live database password (live project: Settings -> Database)
#   - The test project's "Session pooler" connection string and its password
#     (test project: click "Connect" at the top -> Session pooler)
#
# How to run, from the project folder:
#   ./scripts/make-test-copy.sh

set -euo pipefail

LIVE_REF="uejryzioxogquflijgyf"
LIVE_HOST="aws-0-us-west-2.pooler.supabase.com"
PORT="5432"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/snt-test-copy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT   # the copy contains personal data; never leave it lying around

find_tool() {
  for c in "$(command -v "$1" 2>/dev/null || true)" \
           "/opt/homebrew/opt/libpq/bin/$1" "/usr/local/opt/libpq/bin/$1"; do
    if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return; fi
  done
}
PG_DUMP="$(find_tool pg_dump)"; PSQL="$(find_tool psql)"
if [ -z "$PG_DUMP" ] || [ -z "$PSQL" ]; then
  echo "ERROR: PostgreSQL tools not found. On a Mac:  brew install libpq"; exit 1
fi

echo "=============================================================="
echo " Make a TEST copy of the Sensor Network Tracker database"
echo "=============================================================="
echo
echo "Paste the TEST project's Session pooler connection string."
echo "(It looks like: postgresql://postgres.abcd...:[YOUR-PASSWORD]@aws-0-...pooler.supabase.com:5432/postgres )"
read -r -p "> " TEST_URL
# Pull the user and host out of the string; the password is asked separately.
TEST_USER="$(printf '%s' "$TEST_URL" | sed -E 's#^postgres(ql)?://([^:@]+).*#\2#')"
TEST_HOST="$(printf '%s' "$TEST_URL" | sed -E 's#^.*@([^:/]+).*#\1#')"
TEST_REF="${TEST_USER#postgres.}"
if [ -z "$TEST_USER" ] || [ -z "$TEST_HOST" ] || [ "$TEST_USER" = "$TEST_URL" ] || [ "$TEST_REF" = "$TEST_USER" ]; then
  echo "ERROR: that doesn't look like a Session pooler connection string. Nothing was done."; exit 1
fi
if [ "$TEST_REF" = "$LIVE_REF" ]; then
  echo "STOP: that is the LIVE project, not a test project. Nothing was done."; exit 1
fi
echo "Test project: $TEST_REF  (host $TEST_HOST)"
echo

read -r -s -p "LIVE database password: " LIVE_PW; echo
read -r -s -p "TEST database password: " TEST_PW; echo
[ -n "$LIVE_PW" ] && [ -n "$TEST_PW" ] || { echo "Both passwords are needed. Nothing was done."; exit 1; }

live() { PGHOST="$LIVE_HOST" PGPORT="$PORT" PGDATABASE=postgres PGUSER="postgres.$LIVE_REF" PGPASSWORD="$LIVE_PW" PGSSLMODE=require "$@"; }
test_db() { PGHOST="$TEST_HOST" PGPORT="$PORT" PGDATABASE=postgres PGUSER="$TEST_USER" PGPASSWORD="$TEST_PW" PGSSLMODE=require "$@"; }

echo "[1/5] Checking both connections ..."
live "$PSQL" -Atqc "select 'live ok'"
test_db "$PSQL" -Atqc "select 'test ok'"

# Safety: the test project must be empty (no app tables yet).
EXISTING="$(test_db "$PSQL" -Atqc "select count(*) from pg_tables where schemaname='public'")"
if [ "$EXISTING" != "0" ]; then
  echo "STOP: the test project already has $EXISTING table(s) in it."
  echo "This script only fills an EMPTY project. Create a fresh project (or delete"
  echo "and recreate this one) and run again. Nothing was changed."
  exit 1
fi

echo "[2/5] Reading the live database (read-only) ..."
COMMON=(--no-owner --no-privileges)
live "$PG_DUMP" "${COMMON[@]}" --schema=public --schema-only -f "$WORK/schema.sql"
live "$PG_DUMP" "${COMMON[@]}" --schema=public --data-only   -f "$WORK/public-data.sql"
live "$PG_DUMP" "${COMMON[@]}" --data-only \
     --table=auth.users --table=auth.identities --table=auth.mfa_factors \
     -f "$WORK/auth-data.sql"

# Lines a newer pg_dump writes that an older server or an existing schema
# would reject; harmless to drop.
sed -i.bak -E '/^SET transaction_timeout/d; /^CREATE SCHEMA public;/d; /^COMMENT ON SCHEMA public /d' \
    "$WORK/schema.sql" "$WORK/public-data.sql" "$WORK/auth-data.sql"

echo "[3/5] Creating the app's tables, functions and rules in TEST ..."
test_db "$PSQL" -q -v ON_ERROR_STOP=1 -f "$WORK/schema.sql"

echo "[4/5] Copying logins and data into TEST ..."
{
  echo "SET session_replication_role = replica;"   # load in any order; skip triggers
  cat "$WORK/auth-data.sql" "$WORK/public-data.sql"
  echo "SET session_replication_role = origin;"
} > "$WORK/load.sql"
test_db "$PSQL" -q -v ON_ERROR_STOP=1 --single-transaction -f "$WORK/load.sql"

echo "[5/5] Comparing row counts (live vs test) ..."
COUNT_EXACT="do \$\$ declare r record; n bigint; begin
  for r in select tablename from pg_tables where schemaname='public' order by 1 loop
    execute format('select count(*) from public.%I', r.tablename) into n;
    raise notice '%', rpad(r.tablename, 24) || n;
  end loop; end \$\$;"
live    "$PSQL" -q -c "$COUNT_EXACT" 2>&1 | sed -n 's/^NOTICE:  //p' > "$WORK/live-counts.txt"
test_db "$PSQL" -q -c "$COUNT_EXACT" 2>&1 | sed -n 's/^NOTICE:  //p' > "$WORK/test-counts.txt"
if diff -q "$WORK/live-counts.txt" "$WORK/test-counts.txt" >/dev/null; then
  echo "   All tables match:"; sed 's/^/     /' "$WORK/test-counts.txt"
else
  echo "   WARNING: counts differ (live | test):"
  paste "$WORK/live-counts.txt" "$WORK/test-counts.txt" | sed 's/^/     /'
fi
unset LIVE_PW TEST_PW

echo
echo "=============================================================="
echo " Done. The TEST project ($TEST_REF) now holds a copy of the app."
echo " It contains real contact details: keep it private, and delete the"
echo " test project when testing is finished (Settings -> General -> Delete)."
echo "=============================================================="
