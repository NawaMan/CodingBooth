#!/bin/bash
# Print the link-check results recorded in the SQLite database.
#   ./check.sh [db-file]     default: linkcheck.db
set -euo pipefail
cd "$(dirname "$0")"

DB="${1:-linkcheck.db}"

if [[ ! -f "$DB" ]]; then
    echo "No database at '$DB' yet — run ./run.sh first." >&2
    exit 1
fi

echo "=== Recorded checks in $DB ==="
sqlite3 -header -column "$DB" \
    "SELECT id, checked_at, status, url FROM checks ORDER BY id;"

echo ""
echo "=== Summary by status ==="
sqlite3 -header -column "$DB" \
    "SELECT status, COUNT(*) AS count FROM checks GROUP BY status ORDER BY count DESC;"
