#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Starts the Sales Explorer server as a daemon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$HOME/.sales-explorer.pid"
LOG_FILE="$HOME/.sales-explorer.log"

# Install dependencies if needed
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
  echo "📦 Installing Sales Explorer dependencies..."
  npm install --prefix "$SCRIPT_DIR" --no-audit --no-fund 2>&1
fi

# Check if already running
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "ℹ️  Sales Explorer already running (PID: $(cat "$PID_FILE"))"
  exit 0
fi

# Start server as daemon
setsid bash -c "exec node $SCRIPT_DIR/server.js" > "$LOG_FILE" 2>&1 &
echo "$!" > "$PID_FILE"

echo "🚀 Sales Explorer started (PID: $!, port: 13000)"
echo "   Log: $LOG_FILE"
