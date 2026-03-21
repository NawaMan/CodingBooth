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
  VERSION  Freeplane version (default: 1.12.8)

Examples:
  $0             # install with default version
  $0 1.12.8      # specific version

Notes:
- Downloads Freeplane .deb from GitHub releases (pinned version)
- Requires a desktop environment
- Installs Java (if not present)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- defaults / args ----
FREEPLANE_VERSION="${1:-1.12.8}"

export DEBIAN_FRONTEND=noninteractive

# ---- install Java if not present ----
if command -v java >/dev/null 2>&1; then
  echo "• Java already installed: $(java -version 2>&1 | head -1)"
else
  echo "• Installing Java (default-jre) ..."
  apt-get update
  apt-get install -y --no-install-recommends default-jre-headless
  rm -rf /var/lib/apt/lists/*
fi

# ---- install xdg-utils (needed for desktop integration) ----
apt-get update
apt-get install -y --no-install-recommends xdg-utils
rm -rf /var/lib/apt/lists/*

# ---- download and install Freeplane .deb ----
DEB_FILE="/tmp/freeplane_${FREEPLANE_VERSION}.deb"

echo "• Downloading Freeplane ${FREEPLANE_VERSION} ..."
curl -fsSL -o "$DEB_FILE" \
  "https://github.com/freeplane/freeplane/releases/download/release-${FREEPLANE_VERSION}/freeplane_${FREEPLANE_VERSION}~upstream-1_all.deb"

echo "• Installing Freeplane ..."
apt-get update
apt-get install -y --no-install-recommends "$DEB_FILE" || {
  # Fix broken dependencies if needed
  apt-get install -f -y --no-install-recommends
}
rm -f "$DEB_FILE"
rm -rf /var/lib/apt/lists/*

# ---- summary ----
echo ""
echo "✅ Freeplane installed."
echo "   Version: ${FREEPLANE_VERSION}"
echo ""
echo "ℹ️  Launch: freeplane"
