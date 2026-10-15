#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.1

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
- Installs DBeaver Community Edition via .deb package (amd64 or arm64)
- arm64 needs latest or 25.3.1+; older releases ship no arm64 .deb
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

case "$(dpkg --print-architecture)" in
  amd64) DEB_ARCH=amd64; GH_ARCH=x86_64  ;;
  arm64) DEB_ARCH=arm64; GH_ARCH=aarch64 ;;
  *) echo "❌ Unsupported architecture: $(dpkg --print-architecture) (DBeaver ships amd64 and arm64)" >&2; exit 1 ;;
esac

# "latest" comes from dbeaver.io, which redirects to the newest release per architecture.
# A pinned version comes from its GitHub release, whose .deb names changed at 25.3.5:
# dbeaver-ce-<ver>-linux-<x86_64|aarch64>.deb from then on, dbeaver-ce_<ver>_<amd64|arm64>.deb
# before. arm64 .debs start at 25.3.1.
GH_BASE="https://github.com/dbeaver/dbeaver/releases/download/${DBEAVER_VERSION}"
if [[ "$DBEAVER_VERSION" == "latest" ]]; then
  DEB_URLS=("https://dbeaver.io/files/dbeaver-ce_latest_${DEB_ARCH}.deb")
else
  DEB_URLS=("${GH_BASE}/dbeaver-ce-${DBEAVER_VERSION}-linux-${GH_ARCH}.deb"
            "${GH_BASE}/dbeaver-ce_${DBEAVER_VERSION}_${DEB_ARCH}.deb")
fi

echo "• Downloading DBeaver CE (${DBEAVER_VERSION}, ${DEB_ARCH}) ..."
DEB_FILE="/tmp/dbeaver-ce.deb"
downloaded=false
for url in "${DEB_URLS[@]}"; do
  if curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "$DEB_FILE" "$url"; then
    downloaded=true
    break
  fi
done
if [[ "$downloaded" != true ]]; then
  echo "❌ No DBeaver CE ${DBEAVER_VERSION} .deb for ${DEB_ARCH}." >&2
  [[ "$DEB_ARCH" == arm64 ]] && echo "   arm64 .debs exist from 25.3.1 on." >&2
  exit 1
fi

echo "• Installing DBeaver CE ..."
apt-get update
apt-get install -y --no-install-recommends "$DEB_FILE" || {
  # Fix broken dependencies and retry
  apt-get install -f -y --no-install-recommends
}
rm -f "$DEB_FILE"
rm -rf /var/lib/apt/lists/*

# ---- desktop shortcut ----
# Register the DBeaver desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh dbeaver-ce.desktop

# ---- summary ----
INSTALLED_VERSION=$(dbeaver-ce --version 2>/dev/null || dpkg -s dbeaver-ce 2>/dev/null | grep '^Version:' | cut -d' ' -f2 || echo "$DBEAVER_VERSION")
echo ""
echo "✅ DBeaver CE installed."
echo "   Version: ${INSTALLED_VERSION}"
echo "   Launch:  dbeaver-ce (or from desktop menu)"
