#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Heavy: the first run downloads Mathlib's cache (~0.5 GB into the host's ~/.cache/mathlib)
# and unpacks it (~7 GB into this folder's .lake/). Skipped by a default example run; run it
# with --example lean-mathlib-example.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

# --privileged-allowed: the writable $HOME/.cache/mathlib mount (mathlib-cache) would
# otherwise stop a non-interactive start to ask for consent.
if "$BOOTH" --privileged-allowed --port "${CB_PORT:-50861}" -- "./.cb-tests/inBooth--run-all-tests.sh" 2>&1 | tee "$0.out"; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
