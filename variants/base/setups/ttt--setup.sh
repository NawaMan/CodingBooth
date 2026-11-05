#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.3.0

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
- Checks the asset against the release's checksums.txt (published since 1.8.0);
  an older release without one installs with a warning
- Writes /usr/share/startup.d/74-cb-ttt-theme--startup.sh, which at each container
  start sets theme and editor.borderStyle in ~/.config/ttt/settings.json where the
  file has none: \$TTT_THEME (default zenith), \$TTT_BORDER_STYLE (default rounded);
  set either to empty to leave that key to TTT
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

# The release's checksums.txt is "<hash>  <asset>" per line. A mismatch is fatal;
# a release from before the file existed installs with a warning.
if curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
     "https://github.com/eugenioenko/ttt/releases/download/v${VERSION}/checksums.txt" \
     -o "$TMP/checksums.txt" 2>/dev/null; then
  EXPECTED="$(awk -v a="$ASSET" '$2 == a || $2 == "*"a { print $1; exit }' "$TMP/checksums.txt")"
  ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')"
  if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
    echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
    exit 1
  fi
  echo "🔒 Checksum verified."
else
  echo "⚠️  No checksums.txt published for v${VERSION}; skipping checksum verification."
fi

rm -rf /opt/ttt
mkdir -p /opt/ttt
install -m 755 "$TMP/$ASSET" /opt/ttt/ttt
ln -sfn /opt/ttt/ttt /usr/local/bin/ttt

# Default look: zenith with rounded borders, filled in only where settings.json
# has none, so a theme or border picked inside TTT stays. The ttt+theme extension
# picks others through TTT_THEME / TTT_BORDER_STYLE; an empty value skips that key.
THEME_STARTUP=/usr/share/startup.d/74-cb-ttt-theme--startup.sh
install -d "$(dirname "$THEME_STARTUP")"
cat > "$THEME_STARTUP" <<'STARTUP'
#!/usr/bin/env bash
# Written by ttt--setup.sh (CodingBooth). Seeds TTT's theme and border style where
# ~/.config/ttt/settings.json has none; see ttt--setup.sh --help.
set -uo pipefail

THEME="${TTT_THEME-zenith}"
BORDER="${TTT_BORDER_STYLE-rounded}"
[[ -n "$THEME" || -n "$BORDER" ]] || exit 0

CONF="$HOME/.config/ttt/settings.json"
mkdir -p "$(dirname "$CONF")"
[[ -s "$CONF" ]] || echo '{"version":1}' > "$CONF"
tmp="$(mktemp)"
if jq --arg theme "$THEME" --arg border "$BORDER" '
     (if $theme  != "" then .theme //= $theme else . end)
     | (if $border != "" then .editor.borderStyle //= $border else . end)' \
     "$CONF" > "$tmp"; then
  mv "$tmp" "$CONF"
else
  rm -f "$tmp"
  echo "⚠️  TTT theme was not set; ${CONF} is not JSON." >&2
fi
STARTUP
chmod 755 "$THEME_STARTUP"

echo "✅ TTT installed."
echo -n "   ttt → "; ttt --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Open this folder: ttt
- Open a file:      ttt README.md
- Script a session: ttt --size 80x24 --exec 'wait-for Explore; quit'
- Config:           ~/.config/ttt/settings.json
- Look:             zenith theme, rounded borders (ttt+theme picks others)

Notes:
- Workspace search uses rg. This setup installs ripgrep when it is missing.
- The changes panel uses git.
- Select ttt+config-shared to keep ~/.config/ttt in git (.booth/shared).
- Docs: https://tttedit.dev
EON
