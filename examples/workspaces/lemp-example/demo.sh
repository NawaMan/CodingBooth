#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Check the LEMP demo from inside the booth. The booth starts nginx, php-fpm and
# mysqld, and seeds `lemp_demo`.hello on boot, so each command first waits (up to
# 60s) for what it checks.
#   ./demo.sh page     fetch http://localhost/ and print its text; fails unless
#                      the seeded row is on the page
#   ./demo.sh db       the `hello` table, straight from MySQL
#   ./demo.sh status   the three services: nginx, php-fpm and mysqld
set -euo pipefail

DB=lemp_demo
ROW='Hi from MySQL via PHP-FPM!'

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

# running <label> <pgrep pattern> — print the service's oldest PID, or fail.
running() {
  local pid
  pid="$(pgrep -o -f "$2")" || { echo "$1: not running" >&2; return 1; }
  printf '%-8s running (pid %s)\n' "$1:" "$pid"
}

case "${1:-page}" in
  page)
    wait_for "the seeded row in ${DB}.hello" seeded
    wait_for "nginx + PHP-FPM to serve the row" on_page
    curl -fsS http://localhost/ | sed -e 's/<[^>]*>//g' -e 's/^[[:space:]]*//' -e '/^$/d'
    ;;
  db)
    wait_for "the seeded row in ${DB}.hello" seeded
    mysql -t -e 'SELECT * FROM hello' "$DB"
    ;;
  status)
    wait_for "mysqld to answer" mysqladmin ping --silent
    running nginx   'nginx: master'
    running php-fpm 'php-fpm: master'
    running mysqld  'mysqld'
    printf '%-8s %s\n' "mysql:" "$(mysqladmin ping)"
    ;;
  *)
    echo "usage: $0 page|db|status" >&2
    exit 2
    ;;
esac
