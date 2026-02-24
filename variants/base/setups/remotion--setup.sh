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

Examples:
  $0                     # install Remotion CLI with dependencies

Notes:
- Requires Node.js to be installed first
- Installs ffmpeg for video encoding
- Installs Chromium dependencies for headless rendering
- Installs @remotion/cli globally via npm
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- check nodejs ----
if ! command -v node >/dev/null 2>&1; then
  echo "❌ Node.js is required. Install it first (setup nodejs)."
  exit 1
fi
echo "• Node.js found: $(node --version)"

# ---- install system dependencies ----
export DEBIAN_FRONTEND=noninteractive

echo "• Installing ffmpeg and Chromium rendering dependencies ..."
apt-get update
apt-get install -y --no-install-recommends \
  ffmpeg \
  libnss3 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libcups2 \
  libdrm2 \
  libxkbcommon0 \
  libxcomposite1 \
  libxdamage1 \
  libxrandr2 \
  libgbm1 \
  libpango-1.0-0 \
  libcairo2 \
  libasound2t64 \
  libxshmfence1 \
  fonts-noto-color-emoji \
  fonts-liberation
rm -rf /var/lib/apt/lists/*

# ---- install remotion cli ----
echo "• Installing @remotion/cli ..."
npm install -g @remotion/cli

# ---- create profile script ----
LEVEL=65
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-remotion--profile.sh"
cat > "${PROFILE_FILE}" <<'EOF'
# Profile: Remotion
# Point Remotion to system Chromium if available
if [[ -z "${REMOTION_CHROME_EXECUTABLE:-}" ]]; then
  for _cb_chrome in /usr/bin/chromium /usr/bin/chromium-browser /usr/bin/google-chrome; do
    if [[ -x "$_cb_chrome" ]]; then
      export REMOTION_CHROME_EXECUTABLE="$_cb_chrome"
      break
    fi
  done
  unset _cb_chrome
fi
EOF
chmod 644 "${PROFILE_FILE}"

# ---- summary ----
REMOTION_VERSION=$(npx remotion --version 2>/dev/null || echo "unknown")
FFMPEG_VERSION=$(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")

echo ""
echo "✅ Remotion installed."
echo "   remotion → ${REMOTION_VERSION}"
echo "   ffmpeg   → ${FFMPEG_VERSION}"
echo "   node     → $(node --version)"
echo "   Profile  → ${PROFILE_FILE}"
echo ""
echo "ℹ️  Ready to use:"
echo "   Create a new project: npx create-video@latest"
echo "   Render a video:       npx remotion render"
echo "   Start studio:         npx remotion studio"
