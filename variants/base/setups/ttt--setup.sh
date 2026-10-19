#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# ttt--setup.sh — Install the TTT terminal editor from GitHub releases.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest stable TTT
  $0 --version 1.8.0       # pin a release

Notes:
- Installs the Linux release binary under /opt/ttt
- Symlinks /usr/local/bin/ttt at that binary
- Installs ripgrep when rg is not already on PATH (workspace search)
- Supports amd64 and arm64
- The release publishes no checksum file, so the bytes are the GitHub asset
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
TTT_FALLBACK_VER="1.8.0"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Release assets are ttt-linux-amd64 and ttt-linux-arm64.
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64)  ASSET_ARCH="amd64" ;;
  aarch64|arm64) ASSET_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: ${MACHINE} (need x86_64 or aarch64)" >&2; exit 1 ;;
esac

need_pkgs=()
command -v curl >/dev/null 2>&1 || need_pkgs+=(curl ca-certificates)
command -v rg >/dev/null 2>&1 || need_pkgs+=(ripgrep)
if ((${#need_pkgs[@]})); then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "${need_pkgs[@]}"
  rm -rf /var/lib/apt/lists/*
fi

# Tags are vX.Y.Z. releases/latest is the newest stable tag; a rate-limited
# API falls back to the pinned release.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/eugenioenko/ttt/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest TTT release; using ${TTT_FALLBACK_VER}."
    VERSION="$TTT_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a TTT version: '${VERSION}' (expected X.Y.Z, for example 1.8.0)" >&2
  exit 2
fi

ASSET="ttt-linux-${ASSET_ARCH}"
URL="https://github.com/eugenioenko/ttt/releases/download/v${VERSION}/${ASSET}"

echo "⬇️  Installing TTT ${VERSION} (${ASSET_ARCH}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${URL}" >&2
  exit 1
fi

# A failed release URL can still return a 200 HTML page. Require an ELF header.
ELF="$(od -An -t x1 -N 4 "$TMP/$ASSET" | tr -d '[:space:]')"
if [[ "$ELF" != "7f454c46" ]]; then
  echo "❌ Download is not a Linux binary: ${URL}" >&2
  exit 1
fi

rm -rf /opt/ttt
mkdir -p /opt/ttt
install -m 755 "$TMP/$ASSET" /opt/ttt/ttt
ln -sfn /opt/ttt/ttt /usr/local/bin/ttt

echo "✅ TTT installed."
echo -n "   ttt → "; ttt --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Open this folder: ttt
- Open a file:      ttt README.md
- Script a session: ttt --size 80x24 --exec 'wait-for Explore; quit'
- Config:           ~/.config/ttt/settings.json

Notes:
- Workspace search uses rg. This setup installs ripgrep when it is missing.
- The changes panel uses git.
- Select ttt+config-shared to keep ~/.config/ttt in git (.booth/shared).
- Docs: https://tttedit.dev
EON
