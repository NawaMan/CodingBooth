#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

# base, not xfce: the Boothfile still installs Python, Tcl/Tk and Xvfb, and
# Thonny skip_setups when there is no desktop. That is enough to prove both
# turtles without building a desktop image.
"$BOOTH" --variant base --port "${CB_PORT:-50621}" -- "./.cb-tests/inBooth--run-all-tests.sh" 2>&1 | tee "$0.out"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
