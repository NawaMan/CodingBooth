#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

# croft--setup.sh — Install the Croft terminal editor from GitHub releases.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest stable Croft
  $0 --version 0.2.82      # pin a release

Notes:
- Installs the static musl build under /opt/croft
- Symlinks /usr/local/bin/croft at that binary
- Checks the asset against the release SHA256SUMS
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
CROFT_FALLBACK_VER="0.2.82"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Release assets use uname-style names: x86_64 / aarch64.
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64)  ASSET_ARCH="x86_64" ;;
  aarch64|arm64) ASSET_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: ${MACHINE} (need x86_64 or aarch64)" >&2; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar coreutils
  rm -rf /var/lib/apt/lists/*
fi

# Tags are vX.Y.Z. releases/latest is the newest stable tag; a rate-limited
# API falls back to the pinned release.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/vitali87/croft/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest Croft release; using ${CROFT_FALLBACK_VER}."
    VERSION="$CROFT_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a Croft version: '${VERSION}' (expected X.Y.Z, for example 0.2.82)" >&2
  exit 2
fi

TARGET="${ASSET_ARCH}-unknown-linux-musl"
ASSET="croft-${TARGET}.tar.gz"
BASE_URL="https://github.com/vitali87/croft/releases/download/v${VERSION}"

echo "⬇️  Installing Croft ${VERSION} (${TARGET}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ASSET}" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${BASE_URL}/${ASSET}" >&2
  exit 1
fi
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/SHA256SUMS" -o "$TMP/SHA256SUMS"; then
  echo "❌ No SHA256SUMS published for v${VERSION}; refusing to install unverified bytes." >&2
  exit 1
fi

SUM_LINE="$(grep -F " ${ASSET}" "$TMP/SHA256SUMS" || true)"
if [[ -z "$SUM_LINE" ]]; then
  echo "❌ SHA256SUMS has no line for ${ASSET}" >&2
  exit 1
fi
if ! (cd "$TMP" && printf '%s\n' "$SUM_LINE" | sha256sum -c -); then
  echo "❌ SHA256 mismatch for ${ASSET}" >&2
  exit 1
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"
SRC="${TMP}/croft-${TARGET}/croft"
if [[ ! -f "$SRC" ]]; then
  echo "❌ Croft archive did not contain a croft binary" >&2
  exit 1
fi

rm -rf /opt/croft
mkdir -p /opt/croft
install -m 755 "$SRC" /opt/croft/croft
ln -sfn /opt/croft/croft /usr/local/bin/croft

echo "✅ Croft installed."
echo -n "   croft → "; croft --version 2>/dev/null || true

cat <<'EON'
⚠️ WARNING: On the base variant (Console UI) there is no way to quit Croft.
   The browser takes Ctrl+Q and closes the tab, and Croft has no other quit
   command, so you can get stuck in it. Prefer a desktop variant, or run
   croft from a host terminal such as Ghostty, kitty, or WezTerm.

ℹ️ Ready to use:
- Open this folder: croft
- Open a file:      croft . --open-file README.md
- Help:             croft --help
- Config:           ~/.config/croft/config.json

Notes:
- File icons are Nerd Font glyphs. The Console UI draws them with the browser font.
- Select croft+config-shared to keep ~/.config/croft in git (.booth/shared).
- Docs: https://docs.croft.software
EON
