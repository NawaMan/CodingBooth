#!/bin/bash
# Build linkcheck (exercises find_package(CURL) + find_package(SQLite3) + linking),
# run it, and assert it recorded both an ALIVE and a DEAD result in SQLite.
#
# Deterministic and network-independent: a throwaway local HTTP server provides the
# ALIVE case, and the reserved .invalid TLD guarantees a DNS-failure DEAD case.
set -euo pipefail
echo "=== Testing linkcheck (libcurl fetch -> SQLite record) ==="
cd "$(dirname "$0")/.."

python3 -m http.server 18080 --bind 127.0.0.1 >/dev/null 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
sleep 1

urls=/tmp/linkcheck-test-urls.txt
db=/tmp/linkcheck-test.db
rm -f "$db"
cat > "$urls" <<EOF
http://127.0.0.1:18080/
https://this-host-does-not-exist-9x8y7z.invalid/
EOF

./run-linkcheck.sh "$urls" "$db"

alive=$(sqlite3 "$db" "SELECT COUNT(*) FROM checks WHERE status = '200';")
dead=$(sqlite3 "$db"  "SELECT COUNT(*) FROM checks WHERE status LIKE 'DEAD:%';")
echo "recorded in SQLite: alive=$alive dead=$dead"

# The local server must be reachable (ALIVE 200) and .invalid must be DEAD (DNS).
[ "$alive" -ge 1 ] && [ "$dead" -ge 1 ]
