#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--taplo--setup.sh — Install taplo, the TOML toolkit and language server.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest taplo
  $0 --version 0.10.0      # pin a release

Notes:
- Installs the static binary to /usr/local/bin/taplo
- taplo publishes no checksums; the download is over HTTPS from GitHub releases
- Supports amd64 and arm64
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

TAPLO_FALLBACK_VER="0.10.0"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$(uname -m)" in
  x86_64|amd64)  ASSET_ARCH="x86_64" ;;
  aarch64|arm64) ASSET_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $(uname -m) (need x86_64 or aarch64)" >&2; exit 1 ;;
esac

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 3 --retry-delay 2 https://api.github.com/repos/tamasfe/taplo/releases/latest 2>/dev/null \
            | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest taplo release; using ${TAPLO_FALLBACK_VER}."
    VERSION="$TAPLO_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi
if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a taplo version: '${VERSION}' (expected X.Y.Z, for example 0.10.0)" >&2
  exit 2
fi

ASSET="taplo-linux-${ASSET_ARCH}.gz"
URL="https://github.com/tamasfe/taplo/releases/download/${VERSION}/${ASSET}"
echo "⬇️  Installing taplo ${VERSION} (${ASSET_ARCH}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${URL}" >&2
  exit 1
fi
gunzip -c "$TMP/$ASSET" > "$TMP/taplo"
install -m 755 "$TMP/taplo" /usr/local/bin/taplo

echo "✅ taplo installed."
echo -n "   taplo → "; taplo --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Format a file:    taplo fmt Cargo.toml
- Check a file:     taplo check pyproject.toml
- Editors start it as: taplo lsp stdio

Notes:
- Fresh, Helix, and neovim+lsp pick it up for TOML files.
- See: https://taplo.tamasfe.dev
EON
