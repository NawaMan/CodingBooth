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
  $0                         # install latest stable lazysql
  $0 --version 0.5.6         # pin specific version

Notes:
- Installs lazysql to /usr/local/bin/lazysql
- Supports amd64 and arm64
- Not part of the base image by default: select the lazysql template to add it
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
LAZYSQL_DEFAULT_VER="0.5.6"   # fallback when 'latest' cannot be resolved
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
# lazysql's release assets are named "Linux_x86_64" / "Linux_arm64" — a
# different string than the amd64/arm64 dpkg reports, so it needs its own map.
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64" ;;
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
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/jorgerojas26/lazysql/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See lazygit--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest lazysql release; using ${LAZYSQL_DEFAULT_VER}."
    VERSION="$LAZYSQL_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install lazysql ----
echo "⬇️  Installing lazysql v${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/jorgerojas26/lazysql/releases/download/v${VERSION}/lazysql_Linux_${ARCH}.tar.gz" -o "${TMP_DIR}/lazysql.tar.gz"
tar -xzf "${TMP_DIR}/lazysql.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/lazysql" /usr/local/bin/lazysql
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ lazysql installed."
echo -n "   lazysql → "; lazysql -version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Picker mode:       lazysql
- Direct connection: lazysql "postgres://user:pass@host:5432/dbname"

Notes:
- lazysql is a terminal UI for MySQL, PostgreSQL, SQLite3, and MSSQL, taking
  a connection URL as its one argument (or none, to pick a saved one).
- If this booth also has CodingBooth's PostgreSQL or MySQL setup, both
  default to: host localhost, user "$(whoami)" (usually "coder"), no
  password, default port. Neither setup creates a database matching that
  user, so point at one that actually exists (PostgreSQL always has
  "postgres"; MySQL needs no database in the URL path) — e.g.
    lazysql "postgres://coder@localhost:5432/postgres?sslmode=disable"
    lazysql "mysql://coder@localhost:3306/"
- See: https://github.com/jorgerojas26/lazysql
EON
