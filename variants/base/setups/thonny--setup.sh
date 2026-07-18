#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Installs Thonny, a beginner-friendly Python IDE
- Requires a desktop environment
- Requires Python (installed via the python template)
- Installs via apt (Debian/Ubuntu thonny package)
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

# ---- install Thonny ----
export DEBIAN_FRONTEND=noninteractive
echo "• Installing Thonny from apt ..."
apt-get update
apt-get install -y --no-install-recommends thonny
rm -rf /var/lib/apt/lists/*

# ---- summary ----
echo ""
# Register a Thonny desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh thonny
echo "✅ Thonny installed."
echo -n "   thonny → "; thonny --version 2>/dev/null || true
echo ""
echo "ℹ️  Launch: thonny"
echo "   Docs:   https://thonny.org/"
