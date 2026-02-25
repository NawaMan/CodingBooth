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
  VERSION  DBeaver CE version to install (default: latest)

Examples:
  $0           # install latest DBeaver CE
  $0 25.3.5    # install specific version

Notes:
- Requires a desktop variant (desktop-xfce, desktop-kde)
- Installs DBeaver Community Edition via .deb package
- Creates a desktop shortcut
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

# ---- defaults / args ----
DBEAVER_VERSION="${1:-latest}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- install ----
export DEBIAN_FRONTEND=noninteractive

if [[ "$DBEAVER_VERSION" == "latest" ]]; then
  DEB_URL="https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb"
else
  DEB_URL="https://dbeaver.io/files/${DBEAVER_VERSION}/dbeaver-ce_${DBEAVER_VERSION}_amd64.deb"
fi

echo "• Downloading DBeaver CE (${DBEAVER_VERSION}) ..."
DEB_FILE="/tmp/dbeaver-ce.deb"
curl -fsSL -o "$DEB_FILE" "$DEB_URL"

echo "• Installing DBeaver CE ..."
apt-get update
apt-get install -y --no-install-recommends "$DEB_FILE" || {
  # Fix broken dependencies and retry
  apt-get install -f -y --no-install-recommends
}
rm -f "$DEB_FILE"
rm -rf /var/lib/apt/lists/*

# ---- desktop shortcut ----
DESKTOP_FILE_SRC="/usr/share/applications/dbeaver-ce.desktop"
if [[ -f "$DESKTOP_FILE_SRC" ]]; then
  # Create desktop shortcut for all users
  mkdir -p /etc/skel/Desktop
  cp "$DESKTOP_FILE_SRC" /etc/skel/Desktop/
  chmod 755 /etc/skel/Desktop/dbeaver-ce.desktop
fi

# ---- summary ----
INSTALLED_VERSION=$(dbeaver-ce --version 2>/dev/null || dpkg -s dbeaver-ce 2>/dev/null | grep '^Version:' | cut -d' ' -f2 || echo "$DBEAVER_VERSION")
echo ""
echo "✅ DBeaver CE installed."
echo "   Version: ${INSTALLED_VERSION}"
echo "   Launch:  dbeaver-ce (or from desktop menu)"
