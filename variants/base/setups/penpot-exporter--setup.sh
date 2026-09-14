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

Prerequisites:
- The Penpot exporter bundle must be copied to /opt/penpot/exporter
  (typically via COPY --from=penpotapp/exporter:<tag>)
- Playwright browsers at /opt/penpot/browsers
- Node at /opt/penpot-exporter-node (copied from the exporter image)

Notes:
- Installs the native libraries Playwright/Chromium need, plus xvfb
- start-penpot launches the exporter on :6061 when this bundle is present
- This is not a user-facing web UI; the Penpot app talks to it for PNG/PDF export
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

EXPORTER_DIR="/opt/penpot/exporter"
if [[ ! -f "$EXPORTER_DIR/app.js" ]]; then
  echo "❌ Penpot exporter not found at $EXPORTER_DIR"
  echo "   Use COPY --from=penpotapp/exporter:<tag> /opt/penpot/exporter /opt/penpot/exporter"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
echo "• Installing Playwright/Chromium libraries for the Penpot exporter ..."
apt-get update
apt-get install -y --no-install-recommends \
  xvfb \
  fonts-liberation \
  fonts-noto-color-emoji \
  fonts-unifont \
  fonts-freefont-ttf \
  poppler-utils \
  libasound2t64 \
  libatk-bridge2.0-0t64 \
  libatk1.0-0t64 \
  libatspi2.0-0t64 \
  libcairo2 \
  libcups2t64 \
  libdbus-1-3 \
  libdrm2 \
  libgbm1 \
  libglib2.0-0t64 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libx11-6 \
  libxcb1 \
  libxcomposite1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxkbcommon0 \
  libxrandr2
rm -rf /var/lib/apt/lists/*

chmod -R a+rX "$EXPORTER_DIR" /opt/penpot/browsers /opt/penpot-exporter-node 2>/dev/null || true
if id coder >/dev/null 2>&1; then
  chown -R coder:coder "$EXPORTER_DIR" 2>/dev/null || true
  chown -R coder:coder /opt/penpot/browsers /opt/penpot-exporter-node 2>/dev/null || true
fi

PROFILE_FILE="/etc/profile.d/71-cb-penpot-exporter--profile.sh"
cat > "$PROFILE_FILE" <<'PROFILE'
# Penpot exporter (Playwright browsers + bundled Node)
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/penpot/browsers}"
if [[ -d /opt/penpot-exporter-node/bin ]]; then
  case ":$PATH:" in
    *":/opt/penpot-exporter-node/bin:"*) ;;
    *) export PATH="/opt/penpot-exporter-node/bin:$PATH" ;;
  esac
fi
PROFILE
chmod 644 "$PROFILE_FILE"

echo "✅ Penpot exporter libraries installed."
echo "   Bundle:   ${EXPORTER_DIR}"
echo "   Browsers: /opt/penpot/browsers"
echo "   Node:     /opt/penpot-exporter-node"
echo ""
echo "ℹ️ Ready to use:"
echo "   start-penpot launches the exporter on :6061 when this bundle is present."
echo "   Export PNG/PDF from the Penpot UI."
