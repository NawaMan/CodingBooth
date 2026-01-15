#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Builds the http-server image and starts it in daemon mode.
# Sets up port forwarding (socat) from the workspace container to the DinD sidecar.

set -euo pipefail


SERVER_PORT=${SERVER_PORT:-8080}
CONTAINER_NAME="http-server"
PID_FILE="/tmp/http-server-socat.pid"

# Open port forwarding from workspace container to DinD sidecar
SOCAT_PID="$(/usr/local/bin/dind-open-port "$SERVER_PORT")"
echo "$SOCAT_PID" > "$PID_FILE"

DOCKER_BUILDKIT=1 docker build -t http-server .

echo
echo "Starting http-server on port ${SERVER_PORT} in daemon mode..."
docker run -d --name "$CONTAINER_NAME" -p ${SERVER_PORT}:${SERVER_PORT} http-server

echo "Server started. Use ./stop-server.sh to stop it."
