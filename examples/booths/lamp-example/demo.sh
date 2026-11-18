#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Check the LAMP demo from inside the booth. The booth starts mysqld and seeds
# `lamp_demo`.hello on boot, so each command first waits (up to 60s) for that row.
#   ./demo.sh page   fetch http://localhost/ and print its text; fails unless the
#                    seeded row is on the page
#   ./demo.sh db     the `hello` table, straight from MySQL
set -euo pipefail

DB=lamp_demo
ROW='Hi from MySQL!'

# wait_for <description> <command...> — retry the command once a second for 60s.
wait_for() {
  local what="$1"; shift
  for _ in $(seq 60); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "Gave up after 60s waiting for ${what}." >&2
  exit 1
}

seeded()  { mysql -N -e 'SELECT message FROM hello' "$DB" | grep -qxF "$ROW"; }
on_page() { curl -fsS http://localhost/ | grep -qF "$ROW"; }

case "${1:-page}" in
  page)
    wait_for "the seeded row in ${DB}.hello" seeded
    wait_for "Apache to serve the row" on_page
    curl -fsS http://localhost/ | sed -e 's/<[^>]*>//g' -e 's/^[[:space:]]*//' -e '/^$/d'
    ;;
  db)
    wait_for "the seeded row in ${DB}.hello" seeded
    mysql -t -e 'SELECT * FROM hello' "$DB"
    ;;
  *)
    echo "usage: $0 page|db" >&2
    exit 2
    ;;
esac
