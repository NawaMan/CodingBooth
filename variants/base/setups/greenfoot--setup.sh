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
  VERSION  Greenfoot version (default: 3.9.0)

Examples:
  $0             # install with default version
  $0 3.9.0       # specific version

Notes:
- Downloads Greenfoot .deb from greenfoot.org
- Requires a desktop environment
- Requires a JDK (installed via the java template)
- See: https://www.greenfoot.org/
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

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
GREENFOOT_VERSION="${1:-3.9.0}"
GREENFOOT_DEB_TAG="${GREENFOOT_VERSION//./}"

# ---- arch mapping (Greenfoot publishes per-arch .deb files) ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) GREENFOOT_ARCH="x64" ;;
  arm64) GREENFOOT_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive

# ---- install deps ----
echo "• Installing dependencies ..."
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates xdg-utils
rm -rf /var/lib/apt/lists/*

# ---- download Greenfoot .deb ----
DEB_FILE="/tmp/greenfoot_${GREENFOOT_VERSION}.deb"
DOWNLOAD_URL="https://www.greenfoot.org/download/files/Greenfoot-linux-${GREENFOOT_ARCH}-${GREENFOOT_DEB_TAG}.deb"

echo "• Downloading Greenfoot ${GREENFOOT_VERSION} ..."
echo "  From: ${DOWNLOAD_URL}"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "$DEB_FILE" "$DOWNLOAD_URL"

# ---- install Greenfoot ----
echo "• Installing Greenfoot ..."
apt-get update
apt-get install -y --no-install-recommends "$DEB_FILE" || {
  apt-get install -f -y --no-install-recommends
}
rm -f "$DEB_FILE"
rm -rf /var/lib/apt/lists/*

# ---- summary ----
echo ""
# Register a Greenfoot desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh greenfoot
echo "✅ Greenfoot installed."
echo "   Version: ${GREENFOOT_VERSION}"
echo ""
echo "ℹ️  Launch: greenfoot"
echo "   Docs:   https://www.greenfoot.org/doc"
echo "   Note:   Uses the JDK from your java template."
