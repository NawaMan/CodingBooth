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
  PORT  Port for the Logo web editor (default: 18610)

Examples:
  $0            # install with default port 18610
  $0 18700      # use port 18700

Notes:
- Installs Node.js (if not present) and the 'serve' static server
- Copies the vendored JSLogo editor to /opt/logo (no npm build)
- Access: http://localhost:<PORT>
- Hide the green turtle in a program with: hideturtle   (or ht)
- JSLogo is Apache-2.0: https://github.com/inexorabletash/jslogo
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
LOGO_PORT="${1:-18610}"
LOGO_DIR="/opt/logo"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

STARTER_FILE="/usr/local/bin/start-logo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/logo-files"

if [[ ! -d "$FILES_DIR" || ! -f "$FILES_DIR/index.html" ]]; then
  echo "❌ logo-files/ (JSLogo) not found next to $0"
  echo "   Expected: ${FILES_DIR}/index.html"
  exit 1
fi

# ---- check if nodejs is already installed ----
if command -v node >/dev/null 2>&1; then
  echo "• Node.js already installed: $(node --version)"
else
  SETUPS_DIR="/opt/codingbooth/setups"
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

# ---- install vendored JSLogo ----
echo "• Installing JSLogo to ${LOGO_DIR} ..."
mkdir -p "$LOGO_DIR"
cp -a "$FILES_DIR"/. "$LOGO_DIR"/

# ---- create starter script (manual foreground launch) ----
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-__LOGO_PORT__}
URL="http://localhost:${PORT}/"

if curl -sf --max-time 1 "http://127.0.0.1:${PORT}/" 2>/dev/null | grep -q "Logo Interpreter"; then
  echo "Logo editor is already running at ${URL}"
  echo "Hide the green turtle in a program with: hideturtle   (or ht)"
  exit 0
fi

echo "Starting Logo editor on ${URL} ..."
echo "Serving /opt/logo (installed by setup logo, not the project tree)"
echo "Hide the green turtle in a program with: hideturtle   (or ht)"
exec serve -s --no-clipboard /opt/logo -l "$PORT"
STARTER
sed -i "s/__LOGO_PORT__/${LOGO_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
# Register a desktop icon that opens Logo in a browser (desktop variants only).
# Same helper as Excalidraw/Scratch: writes /etc/cb-web-services/logo.conf and
# /usr/share/applications/logo-web.desktop, then cb-desktop-icon.sh seeds
# /etc/skel/Desktop. No-ops when cb-has-desktop.sh fails (base/notebook).
# Resolve the helper from the image setups dir so a project-local copy of
# *this* script still finds it.
CB_SETUPS="${SETUPS_DIR:-/opt/codingbooth/setups}"
WEB_ICON="${CB_SETUPS}/cb-web-icon.sh"
if [ ! -x "$WEB_ICON" ]; then
  WEB_ICON="$(command -v cb-web-icon.sh || true)"
fi
ICON="applications-education"
for candidate in icon.svg favicon.svg favicon.png favicon.ico; do
  found="$(find "$LOGO_DIR" -maxdepth 2 -name "$candidate" -print -quit 2>/dev/null || true)"
  if [ -n "$found" ]; then ICON="$found"; break; fi
done
if [ -n "$WEB_ICON" ] && [ -x "$WEB_ICON" ]; then
  "$WEB_ICON" --id logo --name "Logo" --icon "$ICON" \
    --port "${LOGO_PORT}" --path / --start start-logo
else
  echo "⚠️  cb-web-icon.sh not found; desktop icon skipped"
fi

echo "✅ Logo editor installed."
echo "   Location: ${LOGO_DIR}"
echo "   Port:     ${LOGO_PORT}"
echo "   Starter:  ${STARTER_FILE}"
echo ""
echo "ℹ️  Launch manually: start-logo [PORT]"
echo "   Access: http://localhost:${LOGO_PORT}"
echo "   Hide the turtle: hideturtle   (or ht)"
echo "   Source: https://github.com/inexorabletash/jslogo"
