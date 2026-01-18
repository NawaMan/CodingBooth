#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Starts a simple HTTP server in daemon mode.
# Supports multiple runtimes: node, bun, deno (set via RUNTIME env var)

set -euo pipefail

cd "$(dirname "$0")"

SERVER_PORT=${SERVER_PORT:-8080}
RUNTIME=${RUNTIME:-node}
PID_FILE="/tmp/js-server.pid"
LOG_FILE="/tmp/js-server.log"

# Check if already running
if [[ -f "$PID_FILE" ]]; then
    PID="$(cat "$PID_FILE")"
    if kill -0 "$PID" 2>/dev/null; then
        echo "Server already running (PID: $PID)"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

# Determine runtime command
case "$RUNTIME" in
    node) RUNTIME_CMD="node server.js"    ;;
    bun)  RUNTIME_CMD="bun run server.js" ;;
    deno) RUNTIME_CMD="deno run --allow-net --allow-env --allow-read server.js"  ;;
    *)
        echo "Unknown runtime: $RUNTIME (supported: node, bun, deno)"
        exit 1
        ;;
esac

echo "Starting server with ${RUNTIME} on port ${SERVER_PORT}..."
SERVER_PORT="$SERVER_PORT" nohup $RUNTIME_CMD > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 1

# Verify it started
if [[ -f "$PID_FILE" ]]; then
    PID="$(cat "$PID_FILE")"
    if kill -0 "$PID" 2>/dev/null; then
        echo "Server started (PID: $PID). Use ./stop-server.sh to stop it."
        exit 0
    fi
fi

echo "Failed to start server. Check $LOG_FILE for details."
exit 1
