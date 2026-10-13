#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# differ--setup.sh — Install differ, a terminal reviewer for what a coding
# agent changed, from GitHub releases.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest stable differ
  $0 --version 1.8.1       # pin a release

Notes:
- Installs differ to /usr/local/bin/differ
- Checks the release's checksums.txt before installing
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
DIFFER_FALLBACK_VER="1.8.1"   # used when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Release assets are named after Debian arches: amd64 / arm64.
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) ARCH="$dpkgArch" ;;
  *) echo "❌ Unsupported arch: ${dpkgArch} (need amd64 or arm64)" >&2; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar coreutils
  rm -rf /var/lib/apt/lists/*
fi

# Tags are vX.Y.Z. A rate-limited API falls back to the pinned release.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/JanSmrcka/differ/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest differ release; using ${DIFFER_FALLBACK_VER}."
    VERSION="$DIFFER_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a differ version: '${VERSION}' (expected X.Y.Z, for example 1.8.1)" >&2
  exit 2
fi

BASE_URL="https://github.com/JanSmrcka/differ/releases/download/v${VERSION}"
ASSET="differ_linux_${ARCH}.tar.gz"

echo "⬇️  Installing differ ${VERSION} (${ARCH}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ASSET}" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${BASE_URL}/${ASSET}" >&2
  exit 1
fi
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/checksums.txt" -o "$TMP/checksums.txt"; then
  echo "❌ No checksums.txt published for v${VERSION}; refusing to install unverified bytes." >&2
  exit 1
fi

# checksums.txt is "<hash>  <asset>" for every asset. Compare ours only.
EXPECTED="$(awk -v a="$ASSET" '$2 == a { print $1; exit }' "$TMP/checksums.txt")"
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
  exit 1
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"
if [[ ! -f "$TMP/differ" ]]; then
  echo "❌ differ archive did not contain a differ binary" >&2
  exit 1
fi
install -m 755 "$TMP/differ" /usr/local/bin/differ

echo "✅ differ installed."
echo -n "   differ → "; differ --version </dev/null 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use (inside a git repository):
- Review the changes:     differ review       (j/k move, c comment, J next file)
- Pick the agent:         A                   (claude, codex, aider... in a tmux pane)
- Send the comments:      S                   (pasted into the agent's pane, never submitted)

Notes:
- differ finds agents in other tmux panes, which the Console UI already uses.
- `e` opens $EDITOR at the top of the file; for Fresh, set
  "editor_line_args": "{file}:{line}" in ~/.config/differ/config.json to open at the line.
- Docs: https://github.com/JanSmrcka/differ
EON
