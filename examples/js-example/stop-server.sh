#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Stops the HTTP server.

set -euo pipefail

PID_FILE="/tmp/js-server.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "Server not running (no PID file)"
    exit 0
fi

PID="$(cat "$PID_FILE")"

echo "Stopping server (PID: $PID)..."
if kill "$PID" 2>/dev/null; then
    # Wait for process to terminate
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
fi

rm -f "$PID_FILE"
echo "Server stopped."
