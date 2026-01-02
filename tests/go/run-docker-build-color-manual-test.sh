#!/bin/bash

# Docker Build Color Manual Test Runner
# This script runs the standalone color manual test that shows Docker's colored build output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "Docker Build Color Manual Test"
echo "═══════════════════════════════════════════════════════════"
echo
echo "This demo will show Docker's native colored build output."
echo "Unlike go test, this runs directly in your terminal so you"
echo "should see the blue/green progress bars and colored text."
echo
echo "Press Enter to start..."
read

cd "$SCRIPT_DIR"
go run ./src/cmd/docker-build-color-manual-test/main.go
