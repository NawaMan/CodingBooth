#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# cleanup-after--setup.sh
# 
# Cleanup after setup scripts.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

# APT and package manager caches
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*
rm -rf /opt/pip-cache/*

# Documentation and logs
rm -rf /usr/share/doc/*
rm -rf /usr/share/info/*
rm -rf /var/log/*

# Desktop-specific cleanup (safe to run even if not installed)
apt-get purge -y snapd 2>/dev/null || true
rm -rf /var/lib/snapd /var/snap /snap
rm -rf /var/lib/swcatalog/*
rm -rf /usr/share/wallpapers/*

# VS Code source maps (not needed at runtime)
find /usr/share/code -name "*.map" -type f -delete 2>/dev/null || true
find /usr/local/share/code -name "*.map" -type f -delete 2>/dev/null || true

# Chrome: keep only English locales
find /opt/google/chrome/locales -type f ! -name "en*" -delete 2>/dev/null || true

# Python cleanup
find /opt/local-pythons -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find /opt/venvs -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find /opt/venvs -type d \( -name "tests" -o -name "test" \) -exec rm -rf {} + 2>/dev/null || true
find /usr -name "*.pyc" -type f -delete 2>/dev/null || true