#!/bin/bash
set -euo pipefail
# The game's rules pass their unit tests.
cd "$(dirname "$0")/.."
echo "=== go test ./... ==="
go test ./...
