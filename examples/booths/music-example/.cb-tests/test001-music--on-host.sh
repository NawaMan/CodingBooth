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

# host-audio mounts $XDG_RUNTIME_DIR/pulse/native, and its +jack extension
# $XDG_RUNTIME_DIR/pipewire-0. Only a Linux host with PipeWire has both; the
# in-booth live test skips when this says there is nothing to mount.
EXPECT_HOST_AUDIO=0
if [[ "$(uname -s)" == "Linux" && -S "${XDG_RUNTIME_DIR:-/nonexistent}/pulse/native" \
      && -S "${XDG_RUNTIME_DIR:-/nonexistent}/pipewire-0" ]]; then
    EXPECT_HOST_AUDIO=1
fi

if "$BOOTH" --variant base --port "${CB_PORT:-50881}" --env "CB_EXPECT_HOST_AUDIO=$EXPECT_HOST_AUDIO" \
        -- "./.cb-tests/inBooth--run-all-tests.sh" 2>&1 | tee "$0.out"; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
