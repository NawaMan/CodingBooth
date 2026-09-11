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
  $0                         # install latest stable sqluv
  $0 --version 0.4.8         # pin specific version

Notes:
- Installs sqluv to /usr/local/bin/sqluv
- Supports amd64 and arm64
- Not part of the base image by default: select the sqluv template to add it
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
SQLUV_DEFAULT_VER="0.4.8"   # fallback when 'latest' cannot be resolved
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
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/nao1215/sqluv/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See lazygit--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest sqluv release; using ${SQLUV_DEFAULT_VER}."
    VERSION="$SQLUV_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install sqluv ----
echo "⬇️  Installing sqluv v${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/nao1215/sqluv/releases/download/v${VERSION}/sqluv_${VERSION}_linux_${ARCH}.tar.gz" -o "${TMP_DIR}/sqluv.tar.gz"
tar -xzf "${TMP_DIR}/sqluv.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/sqluv" /usr/local/bin/sqluv
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ sqluv installed."
echo -n "   sqluv → "; sqluv --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: sqluv
- Open a file directly: sqluv mydata.csv
- On first connect to a DBMS, sqluv saves the connection so later launches
  offer it from a list — no need to re-enter it.

Notes:
- sqluv is a terminal UI for MySQL/PostgreSQL/SQLite3/SQL Server, and for
  querying local/HTTPS/S3 CSV, TSV, and LTSV files with SQL.
- If this booth also has CodingBooth's PostgreSQL or MySQL setup, both
  default to: host localhost, user "$(whoami)" (usually "coder"), no
  password, default port — enter those at the sqluv connection prompt.
  Neither setup creates a database matching that user, so for PostgreSQL
  give the database field "postgres" (always present); MySQL needs none.
- See: https://github.com/nao1215/sqluv
EON
