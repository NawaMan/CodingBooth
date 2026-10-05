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
  $0                   # install latest MongoDB
  $0 --version 8.0     # pin to MongoDB 8.0
  $0 --version 7.0     # pin to MongoDB 7.0

Notes:
- Installs MongoDB server (mongod) + shell (mongosh) via official MongoDB apt repo
- The server is NOT started during build (Docker best practice)
- A startup script creates data directories on container start
- User can start mongod manually when needed
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

MONGO_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; MONGO_VERSION="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# Resolve version
if [[ -z "$MONGO_VERSION" || "$MONGO_VERSION" == "latest" ]]; then
  MAJOR_MINOR="8.0"
else
  MAJOR_MINOR="$MONGO_VERSION"
fi

# Determine architecture
ARCH=$(dpkg --print-architecture)

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing MongoDB ${MAJOR_MINOR} ..."

# Install dependencies
apt-get update
apt-get install -y --no-install-recommends gnupg curl

# Add MongoDB signing key
# Staged to a file rather than piped: a retried transfer restarts from the
# beginning, so a consumer already reading the stream would see the truncated
# first attempt followed by the whole body. Downloading first removes that hazard
# and lets --retry-all-errors cover a registry 5xx.
MONGO_KEY="$(mktemp)"
curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "$MONGO_KEY" "https://www.mongodb.org/static/pgp/server-${MAJOR_MINOR}.asc"
gpg --dearmor -o /usr/share/keyrings/mongodb-server-${MAJOR_MINOR}.gpg < "$MONGO_KEY"
rm -f "$MONGO_KEY"

# Add MongoDB apt source
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/mongodb-server-${MAJOR_MINOR}.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/${MAJOR_MINOR} multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-${MAJOR_MINOR}.list

# Install MongoDB
apt-get update
apt-get install -y --no-install-recommends mongodb-org
rm -rf /var/lib/apt/lists/*

# --- startup script: create data directories ---
STARTUP_FILE="/usr/share/startup.d/62-cb-mongodb--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

MONGO_DATA="/home/coder/.mongodb"

# Create data and log directories
mkdir -p "$MONGO_DATA/data" "$MONGO_DATA/log"

# Write minimal mongod.conf if not present
if [ ! -f "$MONGO_DATA/mongod.conf" ]; then
  cat > "$MONGO_DATA/mongod.conf" <<CONF
storage:
  dbPath: ${MONGO_DATA}/data
systemLog:
  destination: file
  path: ${MONGO_DATA}/log/mongod.log
  logAppend: true
net:
  bindIp: 127.0.0.1
  port: 27017
CONF
fi
STARTUP
chmod 755 "$STARTUP_FILE"

INSTALLED_VERSION=$(mongosh --version 2>/dev/null || echo "unknown")
echo ""
echo "✅ MongoDB ${MAJOR_MINOR} installed."
echo "   mongosh version: ${INSTALLED_VERSION}"
echo "   Data directory prepared at /home/coder/.mongodb on container start."
echo ""
echo "ℹ️ Ready to use: mongosh, mongod"
echo "   Start server: mongod --config ~/.mongodb/mongod.conf --fork"
