#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

cleanup() {
    docker stop firewall-example 2>/dev/null || true
    docker rm -f firewall-example 2>/dev/null || true
    for container in $(docker ps -aq --filter "name=firewall-example-.*-dind" 2>/dev/null); do
        docker stop "$container" 2>/dev/null || true
        docker rm -f "$container" 2>/dev/null || true
    done
    for network in $(docker network ls --filter "name=firewall-example-" --format '{{.Name}}' 2>/dev/null | grep -- '-net$'); do
        docker network rm "$network" 2>/dev/null || true
    done
}
trap cleanup EXIT

echo "=== test002: sandbox egress (with DinD reuse) ==="

if ../../../codingbooth --variant base --version latest --port 35210 --name firewall-example --sandbox --dind -- ./.cb-tests/test-on-container.sh; then
    pass "Sandbox DinD reuse test passed"
else
    fail "Sandbox DinD reuse test failed"
fi
