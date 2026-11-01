#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

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
- Comes prebuilt (sha256-checked) from https://github.com/NawaMan/CodingBoothPrebuilt on
  both CPUs (upstream publishes linux amd64 only); a version not prebuilt (yet) is
  built from its release tag with a temporary Go toolchain
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
  x86_64|amd64|aarch64|arm64) ;;
  *) echo "❌ Unsupported arch: $(uname -m) (need x86_64 or arm64)" >&2; exit 1 ;;
esac

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

echo "⬇️  Installing sqls ${VERSION} ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Built as upstream's .goreleaser.yml builds the linux binary: cgo on (the SQLite
# driver is C), -s -w, and the commit in main.revision.
build_from_source() {
  echo "ℹ️  sqls ${VERSION}: not prebuilt for this image; building from source..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends build-essential git
  rm -rf /var/lib/apt/lists/*
  local go_arch go_version
  case "$(uname -m)" in x86_64|amd64) go_arch=amd64 ;; *) go_arch=arm64 ;; esac
  go_version=$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' | jq -er '.[0].version')
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
    "https://go.dev/dl/${go_version}.linux-${go_arch}.tar.gz" -o "$TMP/go.tar.gz"
  tar -xzf "$TMP/go.tar.gz" -C "$TMP"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "v${VERSION}" \
    https://github.com/sqls-server/sqls "$TMP/src"
  (
    cd "$TMP/src"
    export PATH="$TMP/go/bin:$PATH" GOPATH="$TMP/gopath" GOCACHE="$TMP/gocache" CGO_ENABLED=1
    go build -ldflags "-s -w -X main.revision=$(git rev-parse --short HEAD)" -o "$TMP/sqls/sqls" .
  )
}

SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

cb_prebuilt_install sqls "$VERSION" native "$TMP/sqls" || build_from_source
install -m 755 "$TMP/sqls/sqls" /usr/local/bin/sqls

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
