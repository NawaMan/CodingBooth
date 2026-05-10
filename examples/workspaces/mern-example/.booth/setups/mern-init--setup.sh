#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Workspace-local setup for the MERN example:
# - Adds a startup hook that auto-starts mongod.

set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

STARTUP_FILE="/usr/share/startup.d/63-cb-mongod-autostart--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail
CONF="/home/coder/.mongodb/mongod.conf"
if [[ -f "$CONF" ]]; then
  sudo -u coder mongod --config "$CONF" --fork 2>/dev/null || true
fi
STARTUP
chmod 755 "$STARTUP_FILE"

echo "✅ mongod will auto-start on container boot."
