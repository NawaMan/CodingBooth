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
if [ -x "$REPO_ROOT/codingbooth" ]; then
    BOOTH="$REPO_ROOT/codingbooth"
else
    BOOTH="$REPO_ROOT/booth"
fi

# No --variant here on purpose: the booth uses whatever .booth/config.toml
# declares, so the tests exercise the environment the example actually ships.
#
# Pass this as ONE argument. `booth -- a b c` joins its arguments into a single
# string and runs it through a shell, so argv boundaries do not survive.
IN_BOOTH_CMD="./.cb-tests/inBooth--run-all-tests.sh"

"$BOOTH" --port "${CB_PORT:-50412}" -- "$IN_BOOTH_CMD" 2>&1 | tee "$0.out"
# PIPESTATUS[0], not $? — after a pipe, $? is tee's status, which is 0 even when
# the booth failed. That turns a broken run into a green one.
BOOTH_STATUS=${PIPESTATUS[0]}

# A booth that produces no output at all has not run the suite, whatever it
# exited with. Treating that as success is how an empty run passes silently.
if ! grep -q "TEST SUMMARY" "$0.out"; then
    echo -e "${RED}The in-booth test suite produced no summary — it did not run.${NC}"
    echo "See $0.out"
    exit 1
fi

if [ "$BOOTH_STATUS" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
