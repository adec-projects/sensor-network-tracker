#!/usr/bin/env bash
#
# backup-database.sh - make a complete, portable copy of the Sensor Network
# Tracker database to hand to DEC for migration.
#
# What it does: connects to the live Supabase database (read-only), and writes a
# timestamped folder containing the full table structure, all the data, and a
# row-count summary you can check against after DEC loads it into their system.
#
# What you need:
#   1. The database password from the Supabase dashboard
#      (Project Settings -> Database -> Database password).
#   2. The PostgreSQL command-line tools (pg_dump). On a Mac:
#        brew install libpq
#      (No Docker needed.)
#
# How to run, from the project folder:
#   ./scripts/backup-database.sh
#
# Nothing is changed in the database - this only reads.

set -euo pipefail

PROJECT_REF="uejryzioxogquflijgyf"
HOST="aws-0-us-west-2.pooler.supabase.com"
PORT="5432"
OUT="handoff-backup-$(date +%Y%m%d)"

echo "=============================================================="
echo " Sensor Network Tracker - database backup for DEC handoff"
echo "=============================================================="
echo

# Find pg_dump: on the PATH, or where Homebrew's libpq puts it (it isn't
# added to the PATH automatically).
PG_DUMP=""
for c in "$(command -v pg_dump 2>/dev/null || true)" \
         /opt/homebrew/opt/libpq/bin/pg_dump /usr/local/opt/libpq/bin/pg_dump; do
  if [ -n "$c" ] && [ -x "$c" ]; then PG_DUMP="$c"; break; fi
done
if [ -z "$PG_DUMP" ]; then
  echo "ERROR: pg_dump (PostgreSQL tools) isn't installed on this machine."
  echo "On a Mac, install it with:   brew install libpq"
  echo "Then run this script again."
  exit 1
fi

# Ask for the password without showing it on screen.
read -r -s -p "Paste the Supabase database password, then press Enter: " PGPW
echo
if [ -z "${PGPW}" ]; then
  echo "No password entered. Nothing was done."
  exit 1
fi

# Pass connection details via environment variables, so the password never
# appears in the process list or needs URL-encoding.
export PGHOST="$HOST" PGPORT="$PORT" PGDATABASE="postgres"
export PGUSER="postgres.${PROJECT_REF}" PGPASSWORD="$PGPW" PGSSLMODE="require"

mkdir -p "$OUT"
echo
echo "Writing backup into:  $OUT/"
echo

# Only the app's own schema ("public"). Supabase's internal schemas (auth,
# storage, etc.) are platform-specific; user emails and roles are preserved in
# public.profiles and public.allowed_emails. Password hashes are deliberately
# NOT exported.
COMMON=(--schema=public --no-owner --no-privileges)

echo "[1/3] Saving the table structure (schema.sql) ..."
"$PG_DUMP" "${COMMON[@]}" --schema-only -f "$OUT/schema.sql"

echo "[2/3] Saving all the data (data.sql) ..."
"$PG_DUMP" "${COMMON[@]}" --data-only -f "$OUT/data.sql"

echo "[3/3] Counting rows per table (row-counts.txt) ..."
# Count the data rows inside each COPY block of the dump - no extra tools needed.
awk '
  /^COPY /      { t=$2; gsub(/"/,"",t); c=0; incopy=1; next }
  incopy && /^\\\.$/ { printf "%-28s %d\n", t, c; incopy=0; next }
  incopy        { c++ }
' "$OUT/data.sql" | sort > "$OUT/row-counts.txt"
unset PGPASSWORD

echo
echo "=============================================================="
echo " Done. Backup folder: $OUT/"
echo "   schema.sql      - the structure of all tables"
echo "   data.sql        - every row of data"
echo "   row-counts.txt  - how many rows each table has"
echo
echo " Row counts:"
sed 's/^/   /' "$OUT/row-counts.txt"
echo
echo " Next: also download the 'community-files' storage bucket from the"
echo " Supabase dashboard (Storage -> community-files), keep it with this folder,"
echo " and deliver the whole thing to DEC on a secure drive or share (not email)."
echo " This folder contains contact details: do NOT commit it to the repo."
echo "=============================================================="
