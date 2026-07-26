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
  $0                           # install latest duckdb CLI
  $0 --version 1.1.3           # pin specific version

Notes:
- Installs duckdb to /usr/local/bin/duckdb (single static binary)
- DuckDB is an embedded analytical SQL database (no server)
- See: https://duckdb.org
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/duckdb/duckdb/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing duckdb v${VERSION} (${ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/duckdb/duckdb/releases/download/v${VERSION}/duckdb_cli-linux-${ARCH}.zip" -o "$TMP/duckdb.zip"
unzip -q "$TMP/duckdb.zip" -d "$TMP"
install -m 755 "$TMP/duckdb" /usr/local/bin/duckdb

echo "✅ duckdb installed."
echo -n "   duckdb → "; duckdb --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- REPL:           duckdb
- Open a DB file: duckdb mydata.duckdb
- One-off query:  duckdb -c "SELECT 1"
- See: https://duckdb.org
EON
