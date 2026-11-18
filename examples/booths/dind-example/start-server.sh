#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Builds the http-server image and starts it in daemon mode.
# Sets up port forwarding (socat) from the workspace container to the DinD sidecar.

set -euo pipefail


SERVER_PORT=${SERVER_PORT:-8080}
CONTAINER_NAME="http-server"

# --dind under Podman talks to a nested-Podman sidecar (docs/PODMAN_SUPPORT.md),
# not docker:dind. Its compat API rejects the container buildx's own builder
# tries to create: "cannot set cgroup parent if not creating cgroups". The
# legacy builder (DOCKER_BUILDKIT=0) goes straight through the sidecar's build
# endpoint instead and works on both engines, so only force BuildKit on Docker.
if [[ "${BOOTH_ENGINE:-docker}" == "podman" ]]; then
    DOCKER_BUILDKIT=0 docker build -t http-server .
else
    DOCKER_BUILDKIT=1 docker build -t http-server .
fi

echo
echo "Starting http-server on port ${SERVER_PORT} in daemon mode..."
docker run -d --name "$CONTAINER_NAME" -p ${SERVER_PORT}:${SERVER_PORT} http-server

echo "Server started. Use ./stop-server.sh to stop it."
