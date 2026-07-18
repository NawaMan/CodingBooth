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
  VERSION  BlueJ version (default: 5.3.0)

Examples:
  $0             # install with default version
  $0 5.3.0       # specific version

Notes:
- Downloads BlueJ .deb from bluej.org
- Requires a desktop environment
- Requires a JDK (installed via the java template)
- See: https://www.bluej.org/
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
BLUEJ_VERSION="${1:-5.3.0}"
BLUEJ_DEB_TAG="${BLUEJ_VERSION//./}"

export DEBIAN_FRONTEND=noninteractive

# ---- install deps ----
echo "• Installing dependencies ..."
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates xdg-utils
rm -rf /var/lib/apt/lists/*

# ---- download BlueJ .deb ----
DEB_FILE="/tmp/bluej_${BLUEJ_VERSION}.deb"
DOWNLOAD_URL="https://www.bluej.org/download/files/BlueJ-linux-${BLUEJ_DEB_TAG}.deb"

echo "• Downloading BlueJ ${BLUEJ_VERSION} ..."
echo "  From: ${DOWNLOAD_URL}"
curl -fsSL -o "$DEB_FILE" "$DOWNLOAD_URL"

# ---- install BlueJ ----
echo "• Installing BlueJ ..."
apt-get update
apt-get install -y --no-install-recommends "$DEB_FILE" || {
  apt-get install -f -y --no-install-recommends
}
rm -f "$DEB_FILE"
rm -rf /var/lib/apt/lists/*

# ---- summary ----
echo ""
# Register a BlueJ desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh bluej
echo "✅ BlueJ installed."
echo "   Version: ${BLUEJ_VERSION}"
echo ""
echo "ℹ️  Launch: bluej"
echo "   Docs:   https://www.bluej.org/doc/"
echo "   Note:   Uses the JDK from your java template."
