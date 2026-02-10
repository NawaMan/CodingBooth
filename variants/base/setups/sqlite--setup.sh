#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0

Examples:
  $0    # install SQLite 3

Notes:
- Installs SQLite via apt (sqlite3 + libsqlite3-dev)
- Available system-wide
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing SQLite ..."
apt-get update
apt-get install -y --no-install-recommends sqlite3 libsqlite3-dev
rm -rf /var/lib/apt/lists/*

INSTALLED_VERSION=$(sqlite3 --version | awk '{print $1}')
echo ""
echo "✅ SQLite ${INSTALLED_VERSION} installed."
echo "   sqlite3 --version: ${INSTALLED_VERSION}"
echo ""
echo "ℹ️ Ready to use: sqlite3"
