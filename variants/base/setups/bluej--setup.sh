#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION]

Arguments:
  VERSION  BlueJ version (default: 6.0.0)

Examples:
  $0             # install with default version
  $0 6.0.0       # specific version

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
BLUEJ_VERSION="${1:-6.0.0}"
BLUEJ_DEB_TAG="${BLUEJ_VERSION//./}"

export DEBIAN_FRONTEND=noninteractive

# ---- install deps ----
echo "• Installing dependencies ..."
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates xdg-utils
rm -rf /var/lib/apt/lists/*

# ---- download BlueJ .deb ----
DEB_FILE="/tmp/bluej_${BLUEJ_VERSION}.deb"
case "$(dpkg --print-architecture)" in
  amd64) BLUEJ_ARCH="x64"   ;;
  arm64) BLUEJ_ARCH="arm64" ;;
  *)     BLUEJ_ARCH=""      ;;
esac

# Three download schemes: 6.x is on GitHub releases, 5.4.x is per-arch on
# bluej.org, and anything older is one noarch .deb on bluej.org.
IFS=. read -r BLUEJ_MAJOR BLUEJ_MINOR _ <<<"${BLUEJ_VERSION}"
if (( BLUEJ_MAJOR >= 6 )); then
  [[ -n "$BLUEJ_ARCH" ]] || { echo "❌ BlueJ ${BLUEJ_VERSION} has no build for $(dpkg --print-architecture)"; exit 1; }
  DOWNLOAD_URL="https://github.com/k-pet-group/BlueJ-Greenfoot/releases/download/BLUEJ-RELEASE-${BLUEJ_VERSION}/BlueJ-linux-${BLUEJ_ARCH}-${BLUEJ_VERSION}.deb"
elif (( BLUEJ_MAJOR == 5 && BLUEJ_MINOR >= 4 )); then
  [[ -n "$BLUEJ_ARCH" ]] || { echo "❌ BlueJ ${BLUEJ_VERSION} has no build for $(dpkg --print-architecture)"; exit 1; }
  DOWNLOAD_URL="https://www.bluej.org/download/files/BlueJ-linux-${BLUEJ_ARCH}-${BLUEJ_DEB_TAG}.deb"
else
  DOWNLOAD_URL="https://www.bluej.org/download/files/BlueJ-linux-${BLUEJ_DEB_TAG}.deb"
fi

echo "• Downloading BlueJ ${BLUEJ_VERSION} ..."
echo "  From: ${DOWNLOAD_URL}"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "$DEB_FILE" "$DOWNLOAD_URL"

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
