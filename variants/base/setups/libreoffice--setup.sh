#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Installs LibreOffice suite via apt
- Requires a desktop environment
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing LibreOffice ..."
apt-get update
apt-get install -y --no-install-recommends libreoffice
rm -rf /var/lib/apt/lists/*

INSTALLED_VERSION=$(libreoffice --version 2>/dev/null | head -1 || echo "unknown")
echo ""
echo "✅ LibreOffice installed."
echo "   ${INSTALLED_VERSION}"
