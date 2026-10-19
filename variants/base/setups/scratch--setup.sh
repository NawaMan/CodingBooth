#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [PORT]

Arguments:
  PORT  Port for the Scratch web editor (default: 21000)

Examples:
  $0            # install with default port 21000
  $0 18700      # use port 18700

Notes:
- Installs Node.js (if not present) to serve the open-source Scratch 3 GUI
- scratch-gui ${SCRATCH_VERSION} comes prebuilt (sha256-checked) from
  https://github.com/NawaMan/CodingBoothPrebuilt/releases; when that is
  unreachable it is built from the same upstream tag instead
- Serves the static build with 'serve' on the configured port
- Access: http://localhost:<PORT>
- scratch-gui is released under the AGPL-3.0
  (https://github.com/scratchfoundation/scratch-gui)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
SCRATCH_PORT="${1:-21000}"
SCRATCH_DIR="/opt/scratch"
# Upstream archived scratch-gui at 5.3.0, so this is also its last release.
SCRATCH_VERSION="${SCRATCH_VERSION:-5.3.0}"

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

# ---- install the built editor ----
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

build_from_source() {
  local build_dir="/tmp/scratch-build" attempt
  rm -rf "$build_dir"

  echo "• Cloning scratch-gui v${SCRATCH_VERSION} ..."
  # github.com intermittently answers 429/503 during a full build sweep and git has
  # no --retry of its own. Clear the partial clone before retrying — git refuses to
  # clone into a non-empty directory.
  for attempt in 1 2 3; do
    if git clone --depth 1 --branch "v${SCRATCH_VERSION}" \
         https://github.com/scratchfoundation/scratch-gui.git "$build_dir"; then break; fi
    if [ "$attempt" = 3 ]; then echo "❌ scratch-gui clone failed after 3 attempts"; exit 1; fi
    echo "  ⚠️  clone failed — retrying in $((attempt * 5))s ..."
    rm -rf "$build_dir"
    sleep $((attempt * 5))
  done

  cd "$build_dir"

  echo "• Installing dependencies (this may take several minutes) ..."
  npm ci --no-audit --no-fund || npm install --no-audit --no-fund

  echo "• Building Scratch editor ..."
  NODE_ENV=production NODE_OPTIONS=--openssl-legacy-provider npm run build

  echo "• Installing to ${SCRATCH_DIR} ..."
  mkdir -p "$SCRATCH_DIR"
  cp -r build/* "$SCRATCH_DIR"/

  cd /
  rm -rf "$build_dir"
}

rm -rf "$SCRATCH_DIR"
if ! cb_prebuilt_install scratch-gui "$SCRATCH_VERSION" any "$SCRATCH_DIR"; then
  build_from_source
fi
chmod -R a+rX "$SCRATCH_DIR"

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
# Register a desktop icon that opens Scratch in a browser (desktop variants only).
# scratch-gui ships static/favicon.ico, which the build copies into the served
# directory; fall back to a themed icon if that ever moves.
ICON="applications-education"
for candidate in favicon.svg favicon.png favicon.ico; do
  found="$(find "$SCRATCH_DIR" -maxdepth 2 -name "$candidate" -print -quit 2>/dev/null || true)"
  if [ -n "$found" ]; then ICON="$found"; break; fi
done
cb-web-icon.sh --id scratch --name "Scratch" --icon "$ICON" \
  --port "${SCRATCH_PORT}" --path / --start start-scratch

echo "✅ Scratch installed."
echo "   Version:  ${SCRATCH_VERSION}"
echo "   Location: ${SCRATCH_DIR}"
echo "   Port:     ${SCRATCH_PORT}"
echo "   Starter:  ${STARTER_FILE}"
echo ""
echo "ℹ️  Launch manually: start-scratch [PORT]"
echo "   Access: http://localhost:${SCRATCH_PORT}"
echo "   Source: https://github.com/scratchfoundation/scratch-gui"
