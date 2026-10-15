#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--sqls--setup.sh — Install sqls, a SQL language server.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest sqls
  $0 --version 0.2.48      # pin a release

Notes:
- Installs the binary to /usr/local/bin/sqls
- sqls publishes a linux build for amd64 only; on arm64 this script explains and skips
- sqls publishes no checksums; the download is over HTTPS from GitHub releases
- Connections go in ~/.config/sqls/config.yml (see the sqls README)
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

SQLS_FALLBACK_VER="0.2.48"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$(uname -m)" in
  x86_64|amd64) ;;
  aarch64|arm64)
    echo "⚠️  sqls publishes no linux arm64 build; skipping."
    echo "    With the go template selected, 'install go github.com/sqls-server/sqls@latest' builds it."
    exit 0 ;;
  *) echo "❌ Unsupported arch: $(uname -m) (need x86_64)" >&2; exit 1 ;;
esac

if ! command -v unzip >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends unzip
  rm -rf /var/lib/apt/lists/*
fi

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 3 --retry-delay 2 https://api.github.com/repos/sqls-server/sqls/releases/latest 2>/dev/null \
            | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest sqls release; using ${SQLS_FALLBACK_VER}."
    VERSION="$SQLS_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi
if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a sqls version: '${VERSION}' (expected X.Y.Z, for example 0.2.48)" >&2
  exit 2
fi

ZIP="sqls-linux-${VERSION}.zip"
URL="https://github.com/sqls-server/sqls/releases/download/v${VERSION}/${ZIP}"
echo "⬇️  Installing sqls ${VERSION} ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$ZIP"; then
  echo "❌ Download failed: ${URL}" >&2
  exit 1
fi
unzip -q -o "$TMP/$ZIP" sqls -d "$TMP"
install -m 755 "$TMP/sqls" /usr/local/bin/sqls

echo "✅ sqls installed."
echo -n "   sqls → "; sqls --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: sqls
- Fresh, Helix, and neovim+lsp pick it up for .sql files

Notes:
- Completion needs a database connection: ~/.config/sqls/config.yml
  (driver + dataSourceName for postgresql, mysql, sqlite3, ...).
- See: https://github.com/sqls-server/sqls
EON
