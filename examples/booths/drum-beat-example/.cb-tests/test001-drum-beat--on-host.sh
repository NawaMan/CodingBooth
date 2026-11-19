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

# host-audio mounts $XDG_RUNTIME_DIR/pulse/native. Only a Linux host has one; the
# in-booth audio test skips when this says there is nothing to mount.
EXPECT_HOST_AUDIO=0
if [[ "$(uname -s)" == "Linux" && -S "${XDG_RUNTIME_DIR:-/nonexistent}/pulse/native" ]]; then
    EXPECT_HOST_AUDIO=1
fi

if "$BOOTH" --variant base --port "${CB_PORT:-50871}" --env "CB_EXPECT_HOST_AUDIO=$EXPECT_HOST_AUDIO" \
        -- "./.cb-tests/inBooth--run-all-tests.sh" 2>&1 | tee "$0.out"; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
