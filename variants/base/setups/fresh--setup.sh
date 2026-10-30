#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

# fresh--setup.sh — Install the Fresh terminal editor from GitHub releases.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest stable Fresh
  $0 --version 0.5.4       # pin a release

Notes:
- Installs the static musl build under /opt/fresh-editor
- Symlinks /usr/local/bin/fresh at that binary
- Checks the .sha256 published beside the release asset
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
FRESH_FALLBACK_VER="0.5.4"
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
# API falls back to the pinned release. The asset name itself has no version.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/sinelaw/fresh/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest Fresh release; using ${FRESH_FALLBACK_VER}."
    VERSION="$FRESH_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a Fresh version: '${VERSION}' (expected X.Y.Z, for example 0.5.4)" >&2
  exit 2
fi

TARGET="${ASSET_ARCH}-unknown-linux-musl"
ASSET="fresh-editor-${TARGET}.tar.gz"
URL="https://github.com/sinelaw/fresh/releases/download/v${VERSION}/${ASSET}"

echo "⬇️  Installing Fresh ${VERSION} (${TARGET}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${URL}" >&2
  exit 1
fi
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${URL}.sha256" -o "$TMP/$ASSET.sha256"; then
  echo "❌ No .sha256 published for ${ASSET}; refusing to install unverified bytes." >&2
  exit 1
fi

# The sidecar is "<hash>  <asset>". Compare the hash only.
EXPECTED="$(awk 'NF { print $1; exit }' "$TMP/$ASSET.sha256" | tr -d '[:space:]')"
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
  exit 1
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"
SRC="${TMP}/fresh-editor-${TARGET}"
if [[ ! -x "$SRC/fresh" ]]; then
  echo "❌ Fresh archive did not contain a fresh binary" >&2
  exit 1
fi

rm -rf /opt/fresh-editor
mkdir -p /opt/fresh-editor
cp -a "$SRC"/. /opt/fresh-editor/
chmod 755 /opt/fresh-editor/fresh
chmod -R a+rX /opt/fresh-editor
ln -sfn /opt/fresh-editor/fresh /usr/local/bin/fresh

echo "✅ Fresh installed."
echo -n "   fresh → "; fresh --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Open a file:    fresh README.md
- Show config:    fresh --cmd config show
- List grammars:  fresh --cmd grammar list
- Config file:    ~/.config/fresh/config.json

Notes:
- A bare `fresh` starts Orchestrator mode, a background session for the last workspace.
- Upgrade checks and anonymous telemetry (version, OS, architecture, TERM) are on.
  Turn both off with `fresh --no-upgrade-check`, or `"check_for_updates": false`
  in ~/.config/fresh/config.json.
- Change the version by selecting fresh:X.Y.Z and rebuilding the booth.
  `fresh --cmd update` replaces /opt/fresh-editor in place, and that directory is root-owned.
- Select fresh+config-shared to keep ~/.config/fresh in git (.booth/shared).
- Docs: https://getfresh.dev/docs
EON
