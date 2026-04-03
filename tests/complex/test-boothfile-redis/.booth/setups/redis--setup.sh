#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <MAJOR.MINOR>|latest]

Examples:
  $0                   # install latest Redis
  $0 --version 7.4     # pin to Redis 7.4
  $0 --version 7.2     # pin to Redis 7.2

Notes:
- Installs Redis server + tools via official Redis apt repo (packages.redis.io)
- The server is NOT started during build (Docker best practice)
- A startup script creates data directories on container start
- User can start redis-server manually when needed
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

REDIS_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REDIS_VERSION="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# Determine architecture
ARCH=$(dpkg --print-architecture)

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing Redis ..."

# Install dependencies
apt-get update
apt-get install -y --no-install-recommends gnupg curl lsb-release

# Add Redis signing key
curl -fsSL https://packages.redis.io/gpg \
  | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg

# Add Redis apt source
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/redis.list

# Install Redis
apt-get update
if [[ -n "$REDIS_VERSION" && "$REDIS_VERSION" != "latest" ]]; then
  # Try to install a version matching the major.minor prefix
  REDIS_PKG_VER=$(apt-cache madison redis-server 2>/dev/null \
    | awk -F'|' '{print $2}' | tr -d ' ' \
    | grep "^[0-9]*:${REDIS_VERSION}" | head -1 || true)
  if [[ -n "$REDIS_PKG_VER" ]]; then
    apt-get install -y --no-install-recommends \
      "redis-server=${REDIS_PKG_VER}" "redis-tools=${REDIS_PKG_VER}"
  else
    echo "⚠️ Could not find Redis version ${REDIS_VERSION}, installing latest."
    apt-get install -y --no-install-recommends redis-server redis-tools
  fi
else
  apt-get install -y --no-install-recommends redis-server redis-tools
fi
rm -rf /var/lib/apt/lists/*

# --- startup script: create data directories ---
STARTUP_FILE="/usr/share/startup.d/62-cb-redis--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

REDIS_DATA="/home/coder/.redis"

# Create data and log directories
mkdir -p "$REDIS_DATA/data" "$REDIS_DATA/log"
STARTUP
chmod 755 "$STARTUP_FILE"

INSTALLED_VERSION=$(redis-server --version 2>/dev/null || echo "unknown")
echo ""
echo "✅ Redis installed."
echo "   ${INSTALLED_VERSION}"
echo "   Data directory prepared at /home/coder/.redis on container start."
echo ""
echo "ℹ️ Ready to use: redis-server, redis-cli"
echo "   Start server: redis-server --dir ~/.redis/data --daemonize yes"
