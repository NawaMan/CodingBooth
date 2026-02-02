#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for Go example.
# Verifies that the Go project builds and runs correctly.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTH="$SCRIPT_DIR/../../../coding-booth"

# Run inside the container
"$BOOTH" --variant base --port 21000 -- './inBooth--run-all-tests.sh' 2>&1 | tee "$0.out"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
