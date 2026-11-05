#!/usr/bin/env bash
#
# backup-database.sh - make a complete, portable copy of the Sensor Network
# Tracker database to hand to DEC for migration.
#
# What it does: connects to the live Supabase database (read-only), and writes a
# timestamped folder containing the full table structure, all the data, and a
# row-count summary you can check against after DEC loads it into their system.
#
# What you need: the database password from the Supabase dashboard
#   (Project Settings -> Database -> Database password). That's it.
#
# How to run, from the project folder:
#   ./scripts/backup-database.sh
#
# It uses the Supabase command-line tool that's already installed on this machine.
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

if ! command -v supabase >/dev/null 2>&1; then
  echo "ERROR: the 'supabase' tool isn't installed on this machine."
  echo "Install it with:  brew install supabase/tap/supabase"
  exit 1
fi

# Ask for the password without showing it on screen.
read -r -s -p "Paste the Supabase database password, then press Enter: " PGPW
echo
if [ -z "${PGPW}" ]; then
  echo "No password entered. Nothing was done."
  exit 1
fi

# URL-encode the password so special characters don't break the connection.
if command -v python3 >/dev/null 2>&1; then
  ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$PGPW")
else
  ENC="$PGPW"
  echo "(note: python3 not found; if the connection fails and your password has"
  echo " special characters like @ : / # , that's likely why.)"
fi

DBURL="postgresql://postgres.${PROJECT_REF}:${ENC}@${HOST}:${PORT}/postgres"

mkdir -p "$OUT"
echo
echo "Writing backup into:  $OUT/"
echo

echo "[1/3] Saving the table structure (schema.sql) ..."
supabase db dump --db-url "$DBURL" -f "$OUT/schema.sql"

echo "[2/3] Saving all the data (data.sql) ..."
supabase db dump --db-url "$DBURL" --data-only -f "$OUT/data.sql"

echo "[3/3] Counting rows per table (row-counts.txt) ..."
# Count the data rows inside each COPY block of the dump - no extra tools needed.
awk '
  /^COPY /      { t=$2; gsub(/"/,"",t); c=0; incopy=1; next }
  incopy && /^\\\.$/ { printf "%-28s %d\n", t, c; incopy=0; next }
  incopy        { c++ }
' "$OUT/data.sql" | sort > "$OUT/row-counts.txt"

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
echo "=============================================================="
