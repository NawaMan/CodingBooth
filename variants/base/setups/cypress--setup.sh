#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# cypress--setup.sh — Install Cypress with a shared binary cache
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version VERSION]

Options:
  --version VERSION   Cypress npm package version (default: latest)
  -h, --help          Show this help

Notes:
- Requires Node.js (setup nodejs)
- Downloads the Cypress binary into /opt/cypress (shared, world-readable)
- Exports CYPRESS_CACHE_FOLDER so runtime users find the pre-baked binary
- Installs Linux GUI/library dependencies Cypress needs to launch
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

CY_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    --version)  shift; CY_VERSION="${1:-}"; shift ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "❌ Node.js and npm are required. Install them first (setup nodejs)."
  exit 1
fi
echo "• Node.js found: $(node --version)"

export DEBIAN_FRONTEND=noninteractive
echo "• Installing Cypress system dependencies ..."
# https://docs.cypress.io/app/get-started/install-cypress#Linux-Prerequisites
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  libasound2t64 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libcups2 \
  libgbm1 \
  libgtk-3-0 \
  libnss3 \
  libxss1 \
  libxtst6 \
  xauth \
  xvfb \
  fonts-liberation \
  fonts-noto-color-emoji
rm -rf /var/lib/apt/lists/*

CACHE_DIR="/opt/cypress"
export CYPRESS_CACHE_FOLDER="${CACHE_DIR}"
mkdir -p "${CACHE_DIR}"

CY_PKG="cypress"
if [[ -n "${CY_VERSION}" && "${CY_VERSION}" != "latest" ]]; then
  CY_PKG="cypress@${CY_VERSION}"
fi

echo "📦 Installing ${CY_PKG} globally (binary cache: ${CACHE_DIR}) ..."
npm install -g "${CY_PKG}"

# Ensure the binary is fully downloaded/verified at build time.
if command -v cypress >/dev/null 2>&1; then
  cypress install || true
  cypress verify || npx cypress verify
else
  npx cypress install || true
  npx cypress verify
fi

# Cypress verify rewrites binary_state.json at runtime — allow non-root writers.
chmod -R a+rwX "${CACHE_DIR}"

LEVEL=60
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-cypress--profile.sh"
cat > "${PROFILE_FILE}" <<PROF
# Profile: Cypress
export CYPRESS_CACHE_FOLDER=${CACHE_DIR}
PROF
chmod 644 "${PROFILE_FILE}"

CY_VER_OUT=$(cypress --version 2>/dev/null | head -5 || npx cypress --version 2>/dev/null | head -5 || echo "unknown")

echo ""
echo "✅ Cypress installed."
echo "   ${CY_VER_OUT}"
echo "   Cache   : ${CACHE_DIR}"
echo "   Node.js : $(node --version)"
echo "   Profile : ${PROFILE_FILE}"
echo ""
echo "  Ready to use:"
echo "   cypress open     # interactive (needs display / desktop variant)"
echo "   cypress run      # headless CI mode"
echo "   npx cypress run  # from a project that depends on cypress"
