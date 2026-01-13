#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


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

cd "$SCRIPT_DIR/cli"
echo "Building test binary..."
go build -o /tmp/docker-build-color-manual-test ./src/cmd/docker-build-color-manual-test/main.go
cd "$SCRIPT_DIR"
/tmp/docker-build-color-manual-test

