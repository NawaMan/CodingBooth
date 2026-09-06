#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Startup hook that forks mongod on container boot. Pairs with mongodb--setup.sh,
# which only prepares ~/.mongodb — it does not start the server.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Writes /usr/share/startup.d/63-cb-mongodb-start--startup.sh
- Requires mongodb--setup.sh to have run first (mongod on PATH, data dirs at start)
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ $# -gt 0 ]]; then
  echo "❌ Unknown arg: $1" >&2
  usage
  exit 2
fi

if ! command -v mongod >/dev/null 2>&1; then
  echo "❌ mongod not found. Run mongodb--setup.sh first (select mongodb before +start)." >&2
  exit 1
fi

STARTUP_FILE="/usr/share/startup.d/63-cb-mongodb-start--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail
# 62-cb-mongodb--startup.sh has already prepared /home/coder/.mongodb.
CONF="/home/coder/.mongodb/mongod.conf"
if [[ -f "$CONF" ]]; then
  sudo -u coder mongod --config "$CONF" --fork 2>/dev/null || true
fi
STARTUP
chmod 755 "$STARTUP_FILE"

echo "✅ mongod will auto-start on container boot."
