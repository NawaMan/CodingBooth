#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# playwright--setup.sh — Install Playwright test framework with browser binaries
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [BROWSERS]
  $0 [--browsers BROWSERS] [--version VERSION]

Arguments:
  BROWSERS          Comma-separated list of browsers to install
                    (chromium, firefox, webkit, or "all")
                    Default: chromium

Options:
  --browsers BROWSERS   Same as positional argument
  --version  VERSION    Playwright version to install (default: latest)
  -h, --help            Show this help

Examples:
  $0                           # install with chromium only
  $0 chromium,firefox          # install chromium and firefox
  $0 all                       # install all browsers
  $0 --browsers webkit         # install webkit only
  $0 --version 1.50.0          # install specific version
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults ----
BROWSERS="chromium"
PW_VERSION=""

# ---- parse args ----
# First positional arg is browsers (for simple usage: setup playwright chromium,firefox)
if [[ $# -ge 1 && ! "$1" =~ ^-- ]]; then
  BROWSERS="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    --browsers)    shift; BROWSERS="${1:-$BROWSERS}"; shift ;;
    --version)     shift; PW_VERSION="${1:-}"; shift ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- check nodejs ----
if ! command -v node >/dev/null 2>&1; then
  echo "❌ Node.js is required. Install it first (setup nodejs)."
  exit 1
fi
echo "• Node.js found: $(node --version)"

LEVEL=60

PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-playwright--profile.sh"

# Shared, world-readable browser cache so non-root runtime users (e.g. coder)
# can find the pre-baked browsers. Without this, browsers install under
# /root/.cache/ms-playwright and are invisible to the runtime user.
BROWSERS_PATH="/opt/ms-playwright"
export PLAYWRIGHT_BROWSERS_PATH="${BROWSERS_PATH}"

# ---- install playwright ----
PW_PKG="playwright"
if [[ -n "$PW_VERSION" ]]; then
  PW_PKG="playwright@${PW_VERSION}"
fi

echo "📦 Installing ${PW_PKG} globally..."
npm install -g "$PW_PKG"

# ---- install browsers + OS deps ----
# Expand "all" to the full list
if [[ "$BROWSERS" == "all" ]]; then
  BROWSERS="chromium,firefox,webkit"
fi

# Convert comma-separated to space-separated
BROWSER_LIST="${BROWSERS//,/ }"

echo "📦 Installing browsers: ${BROWSER_LIST}"
echo "   Browser cache: ${PLAYWRIGHT_BROWSERS_PATH}"
# Install each browser with system dependencies
# shellcheck disable=SC2086
npx playwright install --with-deps $BROWSER_LIST

# Make the shared browser cache world-readable so non-root users can use it.
chmod -R a+rX "${BROWSERS_PATH}"

# ---- create profile script ----
cat > "${PROFILE_FILE}" <<PROF
# Profile: Playwright
# Use the shared, world-readable browser cache populated at build time.
export PLAYWRIGHT_BROWSERS_PATH=${BROWSERS_PATH}
# Skip browser download on npm install (already installed system-wide)
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
PROF
chmod 644 "${PROFILE_FILE}"

# ---- summary ----
PW_INSTALLED_VERSION=$(npx playwright --version 2>/dev/null || echo "unknown")

echo ""
echo "✅ Playwright installed."
echo "   Version  : ${PW_INSTALLED_VERSION}"
echo "   Browsers : ${BROWSER_LIST}"
echo "   Node.js  : $(node --version)"
echo "   Profile  : ${PROFILE_FILE}"
echo ""
echo "  Ready to use:"
echo "   Init project : npm init playwright@latest"
echo "   Run tests    : npx playwright test"
echo "   Open UI mode : npx playwright test --ui"
echo "   Codegen      : npx playwright codegen"
