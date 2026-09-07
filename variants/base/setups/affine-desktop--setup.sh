#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION]

Arguments:
  VERSION  AFFiNE desktop version (default: 0.27.4)

Examples:
  $0             # install with default version
  $0 0.27.4      # specific version

Notes:
- Downloads the AFFiNE Linux AppImage from official GitHub releases
- Requires a desktop environment
- Linux desktop builds are x86_64 only; arm64 warns and skips
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

arch="$(dpkg --print-architecture)"   # amd64 or arm64
if [[ "$arch" == "arm64" ]]; then
  # AFFiNE ships no linux-arm64 desktop AppImage — only x64. Warn and carry on:
  # a missing desktop app must not take the whole build down.
  cat >&2 <<'WARN'

⚠️  AFFiNE Desktop is not available on arm64 — skipping.

    AFFiNE publishes no linux/arm64 AppImage (GitHub releases are
    affine-*-stable-linux-x64.appimage only), and this booth is being built
    for arm64 — the default on Apple Silicon. The rest of the booth is
    unaffected.

    What to use instead:
      • setup affine-server  — self-hosted web app, official image is multi-arch
                               (booth config: affine-server)
      • AFFiNE on your Mac   — run the macOS client against a self-hosted
                               affine-server, or use it locally.

WARN
  exit 0
fi

# ---- defaults / args ----
AFFINE_DESKTOP_VERSION="${1:-0.27.4}"
AFFINE_DIR="/opt/affine-desktop"
APPIMAGE_NAME="affine-${AFFINE_DESKTOP_VERSION}-stable-linux-x64.appimage"
DOWNLOAD_URL="https://github.com/toeverything/AFFiNE/releases/download/v${AFFINE_DESKTOP_VERSION}/${APPIMAGE_NAME}"

# ---- install dependencies ----
export DEBIAN_FRONTEND=noninteractive
echo "• Installing dependencies ..."
apt-get update
apt-get install -y --no-install-recommends \
  fuse \
  libfuse2 \
  libgtk-3-0 \
  libnotify4 \
  libnss3 \
  libxss1 \
  libxtst6 \
  xdg-utils \
  libatspi2.0-0 \
  libsecret-1-0
rm -rf /var/lib/apt/lists/*

# ---- download AFFiNE ----
mkdir -p "$AFFINE_DIR"

echo "• Downloading AFFiNE Desktop ${AFFINE_DESKTOP_VERSION} (${arch}) ..."
echo "  From: ${DOWNLOAD_URL}"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "${AFFINE_DIR}/${APPIMAGE_NAME}" "$DOWNLOAD_URL"
chmod 755 "${AFFINE_DIR}/${APPIMAGE_NAME}"

# ---- extract AppImage (avoids FUSE requirement at runtime) ----
echo "• Extracting AppImage ..."
cd "$AFFINE_DIR"
"./${APPIMAGE_NAME}" --appimage-extract > /dev/null 2>&1
rm -f "${APPIMAGE_NAME}"

# ---- create launcher script ----
SHIM_BIN="/usr/local/bin/affine-desktop"
cat > "${SHIM_BIN}" <<'LAUNCHER'
#!/usr/bin/env bash
APPDIR="/opt/affine-desktop/squashfs-root"
# Electron in Docker needs --no-sandbox (same class of workaround as Chromium).
if [[ -x "$APPDIR/affine" ]]; then
  exec "$APPDIR/affine" --no-sandbox "$@"
elif [[ -x "$APPDIR/AFFiNE" ]]; then
  exec "$APPDIR/AFFiNE" --no-sandbox "$@"
else
  exec "$APPDIR/AppRun" --no-sandbox "$@"
fi
LAUNCHER
chmod 755 "${SHIM_BIN}"

# ---- icon (AppImage artwork, then a themed fallback) ----
ICON="x-office-document"
for candidate in affine.png AFFiNE.png; do
  found="$(find "$AFFINE_DIR/squashfs-root" -maxdepth 3 -name "$candidate" -print -quit 2>/dev/null || true)"
  if [ -n "$found" ]; then ICON="$found"; break; fi
done
if [ ! -f "$ICON" ]; then
  found="$(find "$AFFINE_DIR/squashfs-root" -path '*hicolor/512x512/apps/*.png' -print -quit 2>/dev/null || true)"
  [ -n "$found" ] && ICON="$found"
fi

# ---- create desktop entry ----
DESKTOP_FILE="/usr/share/applications/affine-desktop.desktop"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=AFFiNE
Comment=Docs, whiteboards, and a local-first knowledge base
Exec=/usr/local/bin/affine-desktop %U
Icon=${ICON}
Terminal=false
Categories=Office;TextEditor;
StartupWMClass=affine
MimeType=x-scheme-handler/affine;
EOF
chmod 644 "$DESKTOP_FILE"
update-desktop-database /usr/share/applications 2>/dev/null || true

# ---- summary ----
echo ""
# Register an AFFiNE desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh affine-desktop.desktop
echo "✅ AFFiNE Desktop installed."
echo "   Version:  ${AFFINE_DESKTOP_VERSION}"
echo "   Location: ${AFFINE_DIR}/squashfs-root/"
echo "   Command:  affine-desktop"
echo ""
echo "ℹ️ Ready to use:"
echo "   affine-desktop"
echo "   Open AFFiNE from the desktop icon on a desktop variant."
