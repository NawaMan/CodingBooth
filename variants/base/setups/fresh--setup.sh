#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.3.0

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
- Writes /usr/share/startup.d/74-cb-fresh--startup.sh, which at each container start
  links the booth-lsp plugin and turns off upgrade checks and telemetry where the
  config does not decide
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

# At each container start, as the user: link the booth-lsp plugin, which starts
# the language servers on PATH and adds an "Install <server>" row to Fresh's LSP
# popup for a missing one. Fresh loads plugins only from the user's plugins
# directory. Anything already at that name, a link or a file of the user's own,
# is left alone; an empty file there turns the plugin off.
# Fresh also checks for upgrades and sends anonymous telemetry unless told not
# to: turn both off, and start on "dark", where the config does not decide. A
# user's own "check_for_updates": true, or a theme from fresh+theme, stays.
STARTUP_FILE=/usr/share/startup.d/74-cb-fresh--startup.sh
install -d "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
# Written by fresh--setup.sh (CodingBooth); see fresh--setup.sh --help.
set -uo pipefail

plugin="$HOME/.config/fresh/plugins/booth-lsp.ts"
if [[ ! -e "$plugin" && ! -L "$plugin" \
      && -r /opt/codingbooth/setups/fresh-plugins/booth-lsp.ts ]]; then
  { mkdir -p "${plugin%/*}" \
      && ln -s /opt/codingbooth/setups/fresh-plugins/booth-lsp.ts "$plugin"; } 2>/dev/null || true
fi

conf="$HOME/.config/fresh/config.json"
if [[ ! -s "$conf" ]]; then
  mkdir -p "${conf%/*}" 2>/dev/null \
    && printf '{"version":1,"check_for_updates":false,"theme":"dark"}\n' > "$conf" 2>/dev/null
elif ! jq -e 'has("check_for_updates") and has("theme")' "$conf" >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if jq 'if has("check_for_updates") then . else .check_for_updates = false end
         | if has("theme") then . else .theme = "dark" end' \
        "$conf" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$conf"
  else
    rm -f "$tmp"
  fi
fi
exit 0
STARTUP
chmod 755 "$STARTUP_FILE"

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
- Upgrade checks and anonymous telemetry (version, OS, architecture, TERM) are off:
  the startup hook writes `"check_for_updates": false` unless the config already
  has the key. Set it to true to turn them on.
- Change the version by selecting fresh:X.Y.Z and rebuilding the booth.
  `fresh --cmd update` replaces /opt/fresh-editor in place, and that directory is root-owned.
- Select fresh+config-shared to keep ~/.config/fresh in git (.booth/shared).
- Docs: https://getfresh.dev/docs
EON
