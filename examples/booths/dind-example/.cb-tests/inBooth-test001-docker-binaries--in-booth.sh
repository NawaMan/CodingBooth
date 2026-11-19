#!/bin/bash
set -euo pipefail
# docker client binaries are installed (daemon/DinD not exercised here)
echo "=== Testing docker binaries ==="
command -v docker
docker --version | grep -q 'Docker version'
docker buildx version | grep -q buildx
