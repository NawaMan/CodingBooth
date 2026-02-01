#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# cleanup-after--setup.sh (dev-friendly, stronger cleanup)
# Cleanup after setup scripts without removing docs/manpages/logs.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

HOME=/root

echo "🧹 Cleaning caches and temp files (dev-friendly)..."

# ---------------- APT caches (safe + high impact) ----------------
rm -rf /var/lib/apt/lists/*

# Keep it explicit and readable
rm -rf /var/cache/apt/archives/* 2>/dev/null || true
rm -rf /var/cache/apt/archives/partial/* 2>/dev/null || true

# Optional dpkg backups
rm -f /var/lib/dpkg/*-old 2>/dev/null || true

# ---------------- General caches ----------------
# Broad root cache cleanup (good for dev images too; rebuilds as needed)
rm -rf /root/.cache/* 2>/dev/null || true

# Targeted pip caches if present
rm -rf /opt/pip-cache/* 2>/dev/null || true
rm -rf /root/.cache/pip 2>/dev/null || true

# ---------------- Temp files (nuke; include dotfiles) ----------------
rm -rf /tmp/* /tmp/.[!.]* /tmp/..?* 2>/dev/null || true
rm -rf /var/tmp/* /var/tmp/.[!.]* /var/tmp/..?* 2>/dev/null || true

# ---------------- Optional space trims ----------------
# GNOME Software / software catalog cache
rm -rf /var/lib/swcatalog/* 2>/dev/null || true

# Wallpapers
# rm -rf /usr/share/wallpapers/* 2>/dev/null || true

# VS Code source maps (not needed at runtime)
find /usr/share/code -name "*.map" -type f -delete 2>/dev/null || true
find /usr/local/share/code -name "*.map" -type f -delete 2>/dev/null || true

# ---------------- Python cleanup ----------------
# Local python trees / venvs: remove caches + obvious test dirs
for d in /opt/local-pythons /opt/venvs; do
  [ -d "$d" ] || continue
  find "$d" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find "$d" -type d \( -name "tests" -o -name "test" \) -prune -exec rm -rf {} + 2>/dev/null || true
done

# Global: remove stray pyc anywhere under /usr (slow-ish but thorough)
find /usr -name "*.pyc" -type f -delete 2>/dev/null || true

echo "✅ Cleanup complete (docs/manpages/logs preserved)."
