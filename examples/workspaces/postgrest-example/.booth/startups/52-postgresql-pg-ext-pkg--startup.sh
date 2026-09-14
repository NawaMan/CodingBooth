#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select postgresql+pg-ext-pkg:pgvector,pg_trgm/postgrest+autostart+expose:+3000

# Enable extensions requested via +pg-ext-pkg, once PostgreSQL (LEVEL 50) is up.
EXT_MANIFEST="/opt/codingbooth/postgresql/extensions.list"

if [ -f "$EXT_MANIFEST" ]; then
  if command -v pg_isready >/dev/null 2>&1; then
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
      pg_isready -q && break
      sleep 1
    done
  fi

  while IFS= read -r ext; do
    [ -z "$ext" ] && continue
    for db in postgres template1; do
      sudo -u postgres psql -d "$db" -c "CREATE EXTENSION IF NOT EXISTS \"$ext\";" >/dev/null 2>&1 \
        || echo "⚠️  Could not enable extension '$ext' in database '$db'" >&2
    done
  done < "$EXT_MANIFEST"
fi
