#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [PORT]

Arguments:
  PORT  Port for the Scratch web editor (default: 18601)

Examples:
  $0            # install with default port 18601
  $0 18700      # use port 18700

Notes:
- Installs Node.js (if not present) and builds the open-source Scratch 3 GUI from source
- Serves the static build with 'serve' on the configured port
- Access: http://localhost:<PORT>
- Scratch is released by MIT under the 3-Clause BSD license
  (https://github.com/scratchfoundation/scratch-gui)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
SCRATCH_PORT="${1:-18601}"
SCRATCH_DIR="/opt/scratch"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

STARTER_FILE="/usr/local/bin/start-scratch"

# ---- check if nodejs is already installed ----
if command -v node >/dev/null 2>&1; then
  echo "• Node.js already installed: $(node --version)"
else
  # Look for nodejs setup in the standard location (built-in setups),
  # then fall back to the same directory as this script.
  SETUPS_DIR="/opt/codingbooth/setups"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$SETUPS_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js ..."
    "$SETUPS_DIR/nodejs--setup.sh" 18
  elif [[ -x "$SCRIPT_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js ..."
    "$SCRIPT_DIR/nodejs--setup.sh" 18
  else
    echo "❌ nodejs--setup.sh not found"
    exit 1
  fi
fi

# ---- install serve globally ----
echo "• Installing 'serve' ..."
npm install -g serve

# ---- clone and build scratch-gui ----
BUILD_DIR="/tmp/scratch-build"
rm -rf "$BUILD_DIR"

echo "• Cloning scratch-gui ..."
git clone --depth 1 https://github.com/scratchfoundation/scratch-gui.git "$BUILD_DIR"

cd "$BUILD_DIR"

echo "• Installing dependencies (this may take several minutes) ..."
npm ci --no-audit --no-fund || npm install --no-audit --no-fund

echo "• Building Scratch editor ..."
NODE_ENV=production NODE_OPTIONS=--openssl-legacy-provider npm run build

# ---- install built files ----
echo "• Installing to ${SCRATCH_DIR} ..."
mkdir -p "$SCRATCH_DIR"
cp -r build/* "$SCRATCH_DIR"/

# ---- clean up build artifacts ----
cd /
rm -rf "$BUILD_DIR"

# ---- create starter script (manual foreground launch) ----
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-__SCRATCH_PORT__}

echo "Starting Scratch editor on http://localhost:$PORT ..."
exec serve -s --no-clipboard /opt/scratch -l "$PORT"
STARTER
sed -i "s/__SCRATCH_PORT__/${SCRATCH_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
echo "✅ Scratch installed."
echo "   Location: ${SCRATCH_DIR}"
echo "   Port:     ${SCRATCH_PORT}"
echo "   Starter:  ${STARTER_FILE}"
echo ""
echo "ℹ️  Launch manually: start-scratch [PORT]"
echo "   Access: http://localhost:${SCRATCH_PORT}"
echo "   Source: https://github.com/scratchfoundation/scratch-gui"
