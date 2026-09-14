#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script apt-installs the packages behind named PostgreSQL extensions.
# It requires postgresql--setup.sh to have been run first.
# Usage: pg-ext--install.sh <extension> [extension...]
# Example: pg-ext--install.sh pgvector pg_trgm postgis

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# cb_retry retries the network-bound apt-get below past a transient registry
# error (a 5xx, a dropped connection) and nothing else, so an unknown extension
# still fails on the first attempt. The lib sits beside this script both in the
# image (/opt/codingbooth/setups/) and in the repo, so a host-run test finds it.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

case "${1:-}" in
  -h|--help)
    echo "Usage: $0 <extension> [extension...]"
    exit 0
    ;;
esac

# Expand comma-separated names into separate arguments, same as pecl--install.sh.
set -- $(echo "$@" | tr ',' ' ')

# No extensions requested is a no-op, not an error: pg-ext-pkg emits
# `install pg-ext ${PG_EXTS}` with the list defaulting to empty, so failing
# here would break every image that selects the extension without naming any.
if [ $# -eq 0 ]; then
  echo "ℹ️  No PostgreSQL extensions requested; nothing to install."
  exit 0
fi

if ! command -v pg_config &>/dev/null; then
  echo "❌ pg_config not found. Run postgresql--setup.sh first." >&2
  exit 1
fi

PG_MAJOR=$(pg_config --version 2>/dev/null | grep -oP '\d+' | head -1)

# Maps a requested extension name to the apt package that provides it.
# Bundled ones ship together in postgresql-contrib; the rest are their own
# package, versioned to match the installed server (same apt.postgresql.org /
# distro repo postgresql--setup.sh already installs from — no extra repo).
resolve_package() {
  case "$1" in
    pg_trgm|hstore|uuid-ossp|pgcrypto|btree_gist|citext|ltree) echo "postgresql-contrib" ;;
    postgis) echo "postgresql-${PG_MAJOR}-postgis-3" ;;
    pgvector) echo "postgresql-${PG_MAJOR}-pgvector" ;;
    pgrouting) echo "postgresql-${PG_MAJOR}-pgrouting" ;;
    *) echo "" ;;
  esac
}

# Maps a requested name to the identifier CREATE EXTENSION actually takes. Almost
# always the same string, but the pgvector *package* does not match its own
# control file: it ships vector.control, so `CREATE EXTENSION pgvector` fails
# with "extension \"pgvector\" is not available" while the package sits right
# there installed and unused. Requiring users to know that split defeats the
# point of naming extensions after their package, so the install script absorbs
# the one exception here instead.
resolve_extname() {
  case "$1" in
    pgvector) echo "vector" ;;
    *) echo "$1" ;;
  esac
}

PACKAGES=()
for ext in "$@"; do
  pkg=$(resolve_package "$ext")
  if [ -z "$pkg" ]; then
    echo "❌ Unknown PostgreSQL extension: '$ext'" >&2
    echo "   Supported: pg_trgm, hstore, uuid-ossp, pgcrypto, btree_gist, citext, ltree, postgis, pgvector, pgrouting" >&2
    exit 1
  fi
  # Dedup (e.g. two contrib-bundled extensions both resolve to postgresql-contrib).
  case " ${PACKAGES[*]:-} " in
    *" $pkg "*) ;;
    *) PACKAGES+=("$pkg") ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing PostgreSQL extension packages: ${PACKAGES[*]}"
cb_retry apt-get update
cb_retry apt-get install -y --no-install-recommends "${PACKAGES[@]}"
# Cache cleanup only shrinks the image layer; a failure here (e.g. no write
# access to this path, as on a host running this script outside a container)
# must not take the extension install down with it.
rm -rf /var/lib/apt/lists/* || true

# Record the CREATE EXTENSION identifiers (not package names, and not
# necessarily the requested names either — see resolve_extname) for the startup
# step to enable once the server is actually running — there is no server to
# run it against at build time.
CB_PG_CONF_DIR="${CB_PG_CONF_DIR:-/opt/codingbooth/postgresql}"
mkdir -p "$CB_PG_CONF_DIR"
: > "$CB_PG_CONF_DIR/extensions.list"
for ext in "$@"; do
  resolve_extname "$ext" >> "$CB_PG_CONF_DIR/extensions.list"
done

echo ""
echo "✅ Extension packages installed: $*"
echo "   Enabled via CREATE EXTENSION on container boot (after PostgreSQL starts)."
