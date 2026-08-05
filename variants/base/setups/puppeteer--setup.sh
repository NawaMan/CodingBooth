#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# puppeteer--setup.sh — Install Puppeteer with a shared Chromium browser cache
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version VERSION]

Options:
  --version VERSION   Puppeteer npm package version (default: latest)
  -h, --help          Show this help

Notes:
- Requires Node.js (setup nodejs)
- Downloads Chrome for Testing into /opt/puppeteer (shared, world-readable)
- Exports PUPPETEER_CACHE_DIR so runtime users find the pre-baked browser
- Installs system libraries needed for headless Chromium
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

PP_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    --version)  shift; PP_VERSION="${1:-}"; shift ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "❌ Node.js and npm are required. Install them first (setup nodejs)."
  exit 1
fi
echo "• Node.js found: $(node --version)"

# Puppeteer's bundled browser is Chrome for Testing, which Google builds for
# linux64 only. On arm64 the npm install either fetches nothing usable or
# fetches an x86-64 binary that dies with "rosetta error: failed to open elf"
# the first time you launch it. Debian Bookworm does build Chromium for arm64,
# so there we skip the download and point Puppeteer at the system browser.
ARCH="$(dpkg --print-architecture)"   # amd64 or arm64
CHROMIUM_FALLBACK=false
[[ "$ARCH" == "arm64" ]] && CHROMIUM_FALLBACK=true

export DEBIAN_FRONTEND=noninteractive
echo "• Installing Chromium runtime libraries ..."
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  fonts-liberation \
  fonts-noto-color-emoji \
  libasound2t64 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libdrm2 \
  libgbm1 \
  libglib2.0-0 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libx11-6 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxkbcommon0 \
  libxrandr2 \
  libxshmfence1 \
  xdg-utils
rm -rf /var/lib/apt/lists/*

# Shared cache so non-root runtime users (e.g. coder) see browsers installed at build time.
CACHE_DIR="/opt/puppeteer"
export PUPPETEER_CACHE_DIR="${CACHE_DIR}"
mkdir -p "${CACHE_DIR}"

PP_PKG="puppeteer"
if [[ -n "${PP_VERSION}" && "${PP_VERSION}" != "latest" ]]; then
  PP_PKG="puppeteer@${PP_VERSION}"
fi

EXECUTABLE_PATH=""
if $CHROMIUM_FALLBACK; then
  echo ""
  echo "⚠️  arm64: Chrome for Testing has no linux-arm64 build."
  echo "    Using Debian Bookworm's Chromium instead — same engine, and Puppeteer"
  echo "    drives it through PUPPETEER_EXECUTABLE_PATH just as well."
  echo ""
  cb-install-chromium.sh
  EXECUTABLE_PATH="$(command -v chromium || command -v chromium-browser || true)"
  [[ -n "$EXECUTABLE_PATH" ]] || { echo "❌ Chromium not found after install"; exit 1; }
fi

echo "📦 Installing ${PP_PKG} globally (browser cache: ${CACHE_DIR}) ..."
# npm install downloads Chrome for Testing into PUPPETEER_CACHE_DIR — pointless
# on arm64, where the download is unusable and Chromium is already in place.
if $CHROMIUM_FALLBACK; then
  PUPPETEER_SKIP_DOWNLOAD=true npm install -g "${PP_PKG}"
else
  npm install -g "${PP_PKG}"
fi

chmod -R a+rX "${CACHE_DIR}"

LEVEL=60
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-puppeteer--profile.sh"
# Global npm modules are not on Node's default require path; expose them.
NODE_GLOBAL="$(npm root -g 2>/dev/null || echo /usr/local/lib/node_modules)"
cat > "${PROFILE_FILE}" <<PROF
# Profile: Puppeteer
# Use the shared, world-readable browser cache populated at build time.
export PUPPETEER_CACHE_DIR=${CACHE_DIR}
# Make the global puppeteer package require()-able without a project install.
export NODE_PATH="${NODE_GLOBAL}\${NODE_PATH:+:\$NODE_PATH}"
# Skip browser download on project-level npm install when the cache is warm.
export PUPPETEER_SKIP_DOWNLOAD=\${PUPPETEER_SKIP_DOWNLOAD:-false}
PROF

if $CHROMIUM_FALLBACK; then
  cat >> "${PROFILE_FILE}" <<PROF
# arm64: no Chrome for Testing build exists, so drive the system Chromium.
# A project-level \`npm i puppeteer\` must not try to download one either.
export PUPPETEER_EXECUTABLE_PATH=${EXECUTABLE_PATH}
export PUPPETEER_SKIP_DOWNLOAD=true
PROF
fi

chmod 644 "${PROFILE_FILE}"

PP_INSTALLED=$(npm list -g puppeteer --depth=0 2>/dev/null | grep puppeteer@ | head -1 || echo "unknown")
BROWSER_COUNT=$(find "${CACHE_DIR}" -type f -name chrome -o -name chrome-headless-shell 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "✅ Puppeteer installed."
echo "   Package  : ${PP_INSTALLED}"
if $CHROMIUM_FALLBACK; then
  echo "   Browser  : ${EXECUTABLE_PATH} (system Chromium — arm64 has no Chrome for Testing)"
else
  echo "   Cache    : ${CACHE_DIR} (${BROWSER_COUNT} chrome binary matches)"
fi
echo "   Node.js  : $(node --version)"
echo "   Profile  : ${PROFILE_FILE}"
echo ""
echo "  Ready to use:"
echo "   node -e \"const p=require('puppeteer'); p.launch().then(b=>b.close())\""
echo "   Or in a project: npm i puppeteer  (reuse PUPPETEER_CACHE_DIR)"
