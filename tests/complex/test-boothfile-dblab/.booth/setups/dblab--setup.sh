#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest stable dblab
  $0 --version 0.50.0        # pin specific version

Notes:
- Installs dblab to /usr/local/bin/dblab
- Supports amd64 and arm64
- Not part of the base image by default: select the dblab template to add it
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
DBLAB_DEFAULT_VER="0.50.0"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# The base image already carries curl, tar, and ca-certificates; only pay for
# apt when this script is run somewhere leaner.
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/danvergara/dblab/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See lazygit--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest dblab release; using ${DBLAB_DEFAULT_VER}."
    VERSION="$DBLAB_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install dblab ----
echo "⬇️  Installing dblab v${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/danvergara/dblab/releases/download/v${VERSION}/dblab_${VERSION}_linux_${ARCH}.tar.gz" -o "${TMP_DIR}/dblab.tar.gz"
tar -xzf "${TMP_DIR}/dblab.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/dblab" /usr/local/bin/dblab
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ dblab installed."
echo -n "   dblab → "; dblab version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Connect directly: dblab --host localhost --port 5432 --user coder --db postgres --driver postgres
- Save it for reuse: add --save-as mybooth, then just: dblab connect mybooth

Notes:
- dblab is a terminal UI for PostgreSQL, MySQL, SQLite3, Oracle, and SQL
  Server, and takes real connection flags (--host/--port/--user/--pass/
  --driver/--db) instead of only prompting interactively.
- If this booth also has CodingBooth's PostgreSQL or MySQL setup, both
  default to: host localhost, user "$(whoami)" (usually "coder"), no
  password, default port (5432 / 3306). Neither setup creates a database
  matching that user, so point --db at one that actually exists — e.g.
    dblab --host localhost --port 5432 --user coder --db postgres --driver postgres
    dblab --host localhost --port 3306 --user coder --driver mysql
- See: https://github.com/danvergara/dblab
EON
