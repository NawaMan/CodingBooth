#!/bin/bash
set -euo pipefail
# kind, kubectl, k9s and docker client are installed (no cluster created)
echo "=== Testing kind binaries ==="
command -v docker
docker --version | grep -q 'Docker version'
kind version | grep -q 'kind v0.27.0'
kubectl version --client | grep -qi 'client version'
command -v k9s
