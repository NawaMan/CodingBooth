#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Check the WordPress demo from inside the booth. Apache and mysqld start with
# the booth, and a startup hook creates the `wordpress` database, so each command
# first waits (up to 60s) for what it checks.
#   ./demo.sh installer   follow http://localhost/ to WordPress's installer page
#   ./demo.sh core        the WordPress core version baked into /var/www/html
#   ./demo.sh db          the MySQL databases; fails unless `wordpress` is one
set -euo pipefail

WEBROOT=/var/www/html

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

has_wp_db() { mysql -N -e 'SHOW DATABASES' | grep -qx wordpress; }

case "${1:-installer}" in
  installer)
    wait_for "Apache to answer on port 80" curl -fsS -o /dev/null http://localhost/
    # Each hop: status line and Location header, then the final page's title.
    curl -sSIL http://localhost/ | grep -iE '^(HTTP/|location:)' | tr -d '\r'
    title="$(curl -fsSL http://localhost/ | grep -o '<title>[^<]*</title>' | sed -e 's/<[^>]*>//g')"
    echo "title: ${title}"
    [[ "$title" == *WordPress* ]] || { echo "Expected a WordPress page." >&2; exit 1; }
    ;;
  core)
    php -r "include '${WEBROOT}/wp-includes/version.php'; echo \"WordPress \$wp_version (PHP \" . PHP_VERSION . \")\n\";"
    ;;
  db)
    wait_for "the wordpress database" has_wp_db
    mysql -t -e 'SHOW DATABASES'
    ;;
  *)
    echo "usage: $0 installer|core|db" >&2
    exit 2
    ;;
esac
