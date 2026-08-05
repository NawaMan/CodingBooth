#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# cb-install-chromium.sh — Install Chromium (and optionally chromedriver) from
# Debian Bookworm, on both amd64 and arm64.
#
# Why this exists: Ubuntu's apt chromium/firefox packages are snap stubs, and
# Google publishes no linux-arm64 build of Chrome or Chrome for Testing — the
# Chrome for Testing API lists linux64 as its only Linux platform. Debian
# Bookworm builds chromium and chromium-driver for arm64, so it is the one
# source that works on Apple Silicon as well as x86.
#
# Three setups need this: chromium-browser (the browser itself), selenium and
# puppeteer (their arm64 fallback). Keeping the Bookworm repo dance in one place
# means the pinning and the cleanup cannot drift between them.
#
# Usage:
#   cb-install-chromium.sh                # chromium only
#   cb-install-chromium.sh --with-driver  # chromium + chromium-driver
#
# Leaves the system Ubuntu-only afterwards: the Bookworm sources are removed and
# apt is refreshed, so later setups see no Debian packages.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

[[ $EUID -eq 0 ]] || { echo "❌ This script must be run as root (use sudo)" >&2; exit 1; }
HOME=/root

WITH_DRIVER=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-driver) WITH_DRIVER=true; shift ;;
    -h|--help) sed -n '7,22p' "$0"; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; exit 2 ;;
  esac
done

PKGS=(chromium)
$WITH_DRIVER && PKGS+=(chromium-driver)

# Idempotent: three setups may each ask for Chromium in one build.
NEEDED=false
for pkg in "${PKGS[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || NEEDED=true
done
if [[ "$NEEDED" == "false" ]]; then
  echo "• Chromium already installed (${PKGS[*]}); skipping."
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")"
ARCH="$(dpkg --print-architecture)"   # amd64 or arm64
echo "🔧 Installing ${PKGS[*]} from Debian Bookworm on Ubuntu ${UBUNTU_CODENAME} for ${ARCH}…"

# --- Add Debian Bookworm repos (with signed-by) ---
install -d -m 0755 /etc/apt/sources.list.d
cat >/etc/apt/sources.list.d/debian-bookworm.list <<'EOF'
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-updates main
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://security.debian.org/debian-security bookworm-security main
EOF
chmod 0644 /etc/apt/sources.list.d/debian-bookworm.list

# --- Prefer Ubuntu by default; only pull what we target from Bookworm ---
cat >/etc/apt/apt.conf.d/99default-release <<EOF
APT::Default-Release "${UBUNTU_CODENAME}";
EOF

apt-get update
apt-get install -y --no-install-recommends -t bookworm "${PKGS[@]}"

# --- IMPORTANT: Remove Debian to avoid future conflicts ---
rm -f /etc/apt/sources.list.d/debian-bookworm.list
rm -f /etc/apt/apt.conf.d/99default-release
apt-get update
echo "🧹 Cleaned up Debian repos; system back to Ubuntu-only."

CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
[[ -n "$CHROMIUM_BIN" ]] || { echo "❌ Could not find chromium binary after installation" >&2; exit 1; }
echo "✅ Chromium installed at: $CHROMIUM_BIN"

if $WITH_DRIVER; then
  DRIVER_BIN="$(command -v chromedriver || true)"
  [[ -n "$DRIVER_BIN" ]] || { echo "❌ Could not find chromedriver after installation" >&2; exit 1; }
  echo "✅ chromedriver installed at: $DRIVER_BIN"
fi
