#!/bin/bash
# Test: PostgreSQL

echo "=== Testing PostgreSQL ==="

# PostgreSQL is keg-only in Homebrew — binaries aren't symlinked to the main bin.
# Add the versioned postgresql bin directory to PATH.
for pg_dir in /home/linuxbrew/.linuxbrew/opt/postgresql@*/bin; do
    [ -d "$pg_dir" ] && export PATH="$pg_dir:$PATH" && break
done

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
