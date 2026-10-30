#!/bin/bash
set -euo pipefail
# kind, kubectl, docker CLI, go, bun and aws binaries exist and print versions (no cluster, no daemon)
echo "=== Testing kind-app tools ==="
kind version
kubectl version --client
docker --version
go version
bun --version
aws --version
