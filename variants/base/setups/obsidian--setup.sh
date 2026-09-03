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
  VERSION  Obsidian version (default: 1.12.4)

Examples:
  $0             # install with default version
  $0 1.12.4      # specific version

Notes:
- Downloads Obsidian AppImage from official GitHub releases
- Requires a desktop environment
- Supports both amd64 and arm64 architectures

─────────────────────────────────────────────────────────────
⚠️  IMPORTANT LICENSE NOTICE
─────────────────────────────────────────────────────────────
• This script only automates **download and installation**
  from Obsidian's official GitHub releases.
  It never includes or redistributes Obsidian binaries.

• Obsidian is free for personal use. Commercial use may
  require a paid license. See: https://obsidian.md/eula

• Obsidian's Terms of Service prohibit redistribution,
  sub-licensing, or making the software available for
  access by third parties.
  See: https://obsidian.md/terms

─────────────────────────────────────────────────────────────
🚫 Actions that are NOT ALLOWED
─────────────────────────────────────────────────────────────
✗ Publishing a Docker image with Obsidian pre-installed
✗ Uploading Obsidian binaries to mirrors, GCS, S3, etc.
✗ Sharing VM/VDI/ISO snapshots with Obsidian included
✗ Making pre-built container images with Obsidian public

─────────────────────────────────────────────────────────────
✅ Allowed actions (SAFE)
─────────────────────────────────────────────────────────────
✔ Sharing this script or a Dockerfile/Boothfile that
  downloads Obsidian at build time from official sources
✔ Using Obsidian in your own private container
✔ Personal, non-commercial use without a license

─────────────────────────────────────────────────────────────
Summary:
  By using this script, you agree to Obsidian's EULA
  and Terms of Service. You are solely responsible for
  ensuring your use complies with their licensing terms.
─────────────────────────────────────────────────────────────
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

# ---- defaults / args ----
OBSIDIAN_VERSION="${1:-1.12.4}"
OBSIDIAN_DIR="/opt/obsidian"

# ---- determine architecture ----
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64)  APPIMAGE_NAME="Obsidian-${OBSIDIAN_VERSION}.AppImage" ;;
  aarch64|arm64) APPIMAGE_NAME="Obsidian-${OBSIDIAN_VERSION}-arm64.AppImage" ;;
  *) echo "❌ Unsupported architecture: $ARCH_RAW"; exit 1 ;;
esac

DOWNLOAD_URL="https://github.com/obsidianmd/obsidian-releases/releases/download/v${OBSIDIAN_VERSION}/${APPIMAGE_NAME}"

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

# ---- download Obsidian ----
mkdir -p "$OBSIDIAN_DIR"

echo "• Downloading Obsidian ${OBSIDIAN_VERSION} (${ARCH_RAW}) ..."
echo "  From: ${DOWNLOAD_URL}"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "${OBSIDIAN_DIR}/${APPIMAGE_NAME}" "$DOWNLOAD_URL"
chmod 755 "${OBSIDIAN_DIR}/${APPIMAGE_NAME}"

# ---- extract AppImage (avoids FUSE requirement at runtime) ----
echo "• Extracting AppImage ..."
cd "$OBSIDIAN_DIR"
"./${APPIMAGE_NAME}" --appimage-extract > /dev/null 2>&1
rm -f "${APPIMAGE_NAME}"

# ---- create launcher script ----
SHIM_BIN="/usr/local/bin/obsidian"
cat > "${SHIM_BIN}" <<'LAUNCHER'
#!/usr/bin/env bash
exec /opt/obsidian/squashfs-root/obsidian --no-sandbox "$@"
LAUNCHER
chmod 755 "${SHIM_BIN}"

# ---- create desktop entry ----
DESKTOP_FILE="/usr/share/applications/obsidian.desktop"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Obsidian
Comment=Knowledge base and note-taking
Exec=/usr/local/bin/obsidian %U
Icon=${OBSIDIAN_DIR}/squashfs-root/usr/share/icons/hicolor/512x512/apps/obsidian.png
Terminal=false
Categories=Office;TextEditor;
StartupWMClass=obsidian
MimeType=x-scheme-handler/obsidian;
EOF
chmod 644 "$DESKTOP_FILE"
update-desktop-database /usr/share/applications 2>/dev/null || true

# ---- summary ----
echo ""
# Register an Obsidian desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh obsidian.desktop
echo "✅ Obsidian installed."
echo "   Version:  ${OBSIDIAN_VERSION}"
echo "   Location: ${OBSIDIAN_DIR}/squashfs-root/"
echo "   Command:  obsidian"
echo ""
echo "⚠️  By using Obsidian, you agree to its EULA: https://obsidian.md/eula"
