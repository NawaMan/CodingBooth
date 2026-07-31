#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# cursor--setup.sh — Install the Cursor editor from its official .deb, then wrap it for containers
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--track <stable|latest>] [--deb-url <url>]

Options:
  --track <track>   Release track to install (default: stable)
  --deb-url <url>   Install this exact .deb instead of resolving a track

Examples:
  $0                              # current stable
  $0 --track latest               # the fast-moving track
  $0 --deb-url https://downloads.cursor.com/.../cursor_3.13.25_amd64.deb

Notes:
- Cursor's download URLs embed a build commit, so there is no version-only
  URL to pin against. To pin a build, resolve it once and pass --deb-url:
    curl -fsSL 'https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable'
  and take the "debUrl" field from the JSON.
- Requires a desktop environment; skipped on non-desktop variants.
- This script only automates download and installation from Cursor's official
  endpoints. It never redistributes Cursor binaries. Cursor's terms apply:
  https://cursor.com/terms-of-service
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }

# This script will always be installed by root.
HOME=/root

TRACK="stable"
DEB_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --track)   shift; TRACK="${1:-stable}"; shift ;;
    --deb-url) shift; DEB_URL="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

CURSOR_NEW_BIN=/usr/bin/cursor
CURSOR_ORG_BIN=/usr/bin/cursor-original
CURSOR_ELECTRON=/usr/share/cursor/cursor

STARTUP_FILE="/usr/share/startup.d/70-cb-cursor--startup.sh"

export DEBIAN_FRONTEND=noninteractive

# ---- base deps ----
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

# ---- resolve the download ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) CURSOR_PLATFORM="linux-x64" ;;
  arm64) CURSOR_PLATFORM="linux-arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)" >&2; exit 1 ;;
esac

if [[ -z "$DEB_URL" ]]; then
  API_URL="https://www.cursor.com/api/download?platform=${CURSOR_PLATFORM}&releaseTrack=${TRACK}"
  echo "🔎 Resolving Cursor (${TRACK}, ${CURSOR_PLATFORM}) ..."
  API_JSON="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$API_URL")"
  DEB_URL="$(printf '%s' "$API_JSON" | grep -oP '"debUrl"\s*:\s*"\K[^"]+')"
  RESOLVED_VER="$(printf '%s' "$API_JSON" | grep -oP '"version"\s*:\s*"\K[^"]+')"
  [[ -n "$DEB_URL" ]] || { echo "❌ Could not resolve a Cursor .deb for ${TRACK}/${CURSOR_PLATFORM}" >&2; exit 1; }
  echo "   Version: ${RESOLVED_VER:-unknown}"
fi

# ---- download and install ----
DEB_FILE="/tmp/cursor_${dpkgArch}.deb"
echo "⬇️  Downloading Cursor ..."
curl -fsSL --retry 3 --retry-delay 2 -o "$DEB_FILE" "$DEB_URL"

echo "📦 Installing Cursor ..."
apt-get update
apt-get install -y --no-install-recommends "$DEB_FILE" || {
  # Fix broken dependencies if needed
  apt-get install -f -y --no-install-recommends
}
rm -f "$DEB_FILE"
rm -rf /var/lib/apt/lists/*

INSTALLED_VERSION="$(dpkg -s cursor 2>/dev/null | grep '^Version:' | awk '{print $2}' || echo "unknown")"

# --- Container-compatible wrapper ---
# The .deb's postinst symlinks /usr/bin/cursor -> /usr/share/cursor/bin/cursor.
# Keep that launcher as -original and put a --no-sandbox wrapper in its place:
# Chromium's sandbox needs privileges a booth deliberately does not have.
if [[ -e "$CURSOR_NEW_BIN" ]]; then
  mv -f "$CURSOR_NEW_BIN" "$CURSOR_ORG_BIN"
else
  ln -sfn /usr/share/cursor/bin/cursor "$CURSOR_ORG_BIN"
fi

cat >"${CURSOR_NEW_BIN}" <<EOF
#!/usr/bin/env bash
exec "$CURSOR_ORG_BIN" \
  --no-sandbox \
  "\${@:-/home/coder/code}"
EOF
chmod 0755 "${CURSOR_NEW_BIN}"

# --- Point the .desktop entry at our wrapper ---
# Shipped as Exec=/usr/share/cursor/cursor, i.e. straight at the Electron binary,
# which would start without --no-sandbox.
for DESKTOP_FILE in /usr/share/applications/cursor.desktop \
                    /usr/share/applications/cursor-url-handler.desktop; do
  if [[ -f "$DESKTOP_FILE" ]]; then
    sed -i "s|Exec=${CURSOR_ELECTRON}|Exec=${CURSOR_NEW_BIN}|g" "$DESKTOP_FILE"
  fi
done

# Register a Cursor desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh cursor.desktop

# ---- Create startup file: runs once per container start as normal user ----
# No build-time values to stamp in, so write it verbatim — envsubst with no
# allowlist would eat $HOME and $CB_SEED_DIR.
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Cursor startup script
# Seeds settings/credentials from cb-home-seed when the user has none yet.
# Cursor keeps its sign-in under ~/.config/Cursor and its CLI state under ~/.cursor.

for pair in ".config/Cursor" ".cursor"; do
    CB_SEED_DIR="/etc/cb-home-seed/${pair}"
    DEST_DIR="$HOME/${pair}"
    if [[ -d "$CB_SEED_DIR" && ! -d "$DEST_DIR" ]]; then
        mkdir -p "$DEST_DIR"
        cp -r "$CB_SEED_DIR/." "$DEST_DIR/"
    fi
done
EOF
chmod 755 "${STARTUP_FILE}"

echo ""
echo "✅ Cursor installed successfully!"
echo "   Version: ${INSTALLED_VERSION}"
echo "   Binary:  ${CURSOR_NEW_BIN} (wraps ${CURSOR_ORG_BIN} with --no-sandbox)"
echo "   Startup: ${STARTUP_FILE}"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Cursor credentials (home-seeding: app may write session data)'
echo '      "-v", "~/.config/Cursor:/etc/cb-home-seed/.config/Cursor:ro",'
echo '      "-v", "~/.cursor:/etc/cb-home-seed/.cursor:ro"'
echo '  ]'
echo ""
