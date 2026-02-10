#!/bin/bash
# Template test: SQLite + PostgreSQL + MySQL (databases)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "sqlite/postgresql/mysql"

booth-collect "
echo -n '1: ' ; command -v sqlite3  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v psql     >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; command -v mysql    >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "SQLite is installed"
assert-line "$tmpfile" "2: " "OK"  "PostgreSQL client is installed"
assert-line "$tmpfile" "3: " "OK"  "MySQL client is installed"
finally
