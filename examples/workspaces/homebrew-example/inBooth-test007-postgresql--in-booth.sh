#!/bin/bash
# Test: PostgreSQL

echo "=== Testing PostgreSQL ==="

PGDATA="/tmp/test-pg-$$"
PGLOG="/tmp/test-pg-$$.log"

cleanup() {
    pg_ctl -D "$PGDATA" stop -m fast 2>/dev/null || true
    rm -rf "$PGDATA" "$PGLOG"
}
trap cleanup EXIT

initdb -D "$PGDATA" > /dev/null
pg_ctl -D "$PGDATA" -l "$PGLOG" start -w
createdb testdb
psql testdb -tc "SELECT 'PostgreSQL works!';"
