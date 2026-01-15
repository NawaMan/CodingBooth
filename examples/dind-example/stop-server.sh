#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Stops the http-server container and closes the port forwarding (socat).

set -euo pipefail


CONTAINER_NAME="http-server"
PID_FILE="/tmp/http-server-socat.pid"

echo "Stopping $CONTAINER_NAME..."
docker stop "$CONTAINER_NAME" 2>/dev/null && docker rm "$CONTAINER_NAME" 2>/dev/null

# Close port forwarding
if [[ -f "$PID_FILE" ]]; then
    SOCAT_PID="$(cat "$PID_FILE")"
    /usr/local/bin/dind-open-port "$SOCAT_PID" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

echo "Server stopped."
