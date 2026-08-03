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
  PORT  Port for the Excalidraw web server (default: 15555)

Examples:
  $0           # install with default port 15555
  $0 16000     # use port 16000

Notes:
- Installs Node.js (if not present) and builds Excalidraw from source
- Serves the static app with 'serve' on the configured port
- Auto-starts in background at container startup
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
EXCALIDRAW_PORT="${1:-15555}"
EXCALIDRAW_VERSION="v0.18.0"
EXCALIDRAW_DIR="/opt/excalidraw"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

STARTER_FILE="/usr/local/bin/start-excalidraw"

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

# ---- install yarn and serve globally ----
echo "• Installing yarn and serve ..."
npm install -g yarn serve

# ---- clone and build excalidraw ----
BUILD_DIR="/tmp/excalidraw-build"
rm -rf "$BUILD_DIR"

echo "• Cloning Excalidraw ${EXCALIDRAW_VERSION} ..."
# github.com intermittently answers 429/503 during a full build sweep and git has
# no --retry of its own. Clear the partial clone before retrying — git refuses to
# clone into a non-empty directory.
for attempt in 1 2 3; do
  if git clone --depth 1 --branch "$EXCALIDRAW_VERSION" \
       https://github.com/excalidraw/excalidraw.git "$BUILD_DIR"; then break; fi
  if [ "$attempt" = 3 ]; then echo "❌ Excalidraw clone failed after 3 attempts"; exit 1; fi
  echo "  ⚠️  clone failed — retrying in $((attempt * 5))s ..."
  rm -rf "$BUILD_DIR"
  sleep $((attempt * 5))
done

cd "$BUILD_DIR"

echo "• Installing dependencies ..."
yarn --network-timeout 600000 --frozen-lockfile || yarn --network-timeout 600000

echo "• Building Excalidraw ..."
NODE_ENV=production yarn build:app:docker

# ---- install built files ----
echo "• Installing to ${EXCALIDRAW_DIR} ..."
mkdir -p "$EXCALIDRAW_DIR"
cp -r excalidraw-app/build/* "$EXCALIDRAW_DIR"/

# ---- clean up build artifacts ----
cd /
rm -rf "$BUILD_DIR"

# ---- create starter script (manual foreground launch) ----
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-__EXCALIDRAW_PORT__}

echo "Starting Excalidraw on http://localhost:$PORT ..."
exec serve -s --no-clipboard /opt/excalidraw -l "$PORT"
STARTER
sed -i "s/__EXCALIDRAW_PORT__/${EXCALIDRAW_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
# Register a desktop icon that opens Excalidraw in a browser (desktop variants only).
cb-web-icon.sh --id excalidraw --name "Excalidraw" --icon applications-internet \
  --port "${EXCALIDRAW_PORT}" --path / --start start-excalidraw

echo "✅ Excalidraw installed."
echo "   Version:  ${EXCALIDRAW_VERSION}"
echo "   Location: ${EXCALIDRAW_DIR}"
echo "   Port:     ${EXCALIDRAW_PORT}"
echo "   Starter:  ${STARTER_FILE}"
echo ""
echo "ℹ️  Launch manually: start-excalidraw [PORT]"
echo "   Access: http://localhost:${EXCALIDRAW_PORT}"
