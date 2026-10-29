#!/bin/bash
set -euo pipefail
# The Appwrite CLI and the Docker tooling for the server are installed.
echo "=== Testing Appwrite CLI ==="
command -v appwrite
appwrite --version
command -v docker
docker --version
docker compose version || docker-compose --version
node --version
