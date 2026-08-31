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
# declares (xfce), so the tests exercise the environment the example actually
# ships rather than a lighter stand-in.
#
# `booth` has no --env flag, so the emulator gate is threaded through the command
# line instead of the environment. The emulator test is opt-in because booting
# Android dominates the run — see inBooth-test003.
#
# Pass this as ONE argument. `booth -- a b c` joins its arguments into a single
# string and runs it through a shell, so argv boundaries and quoting do not
# survive: `-- bash -c "VAR=1 ./script"` arrives as `bash -c VAR=1 ./script`,
# where bash takes "VAR=1" as the whole command and the script path as $0 — a
# silent no-op that exits 0 in two seconds. One pre-joined string has nothing to
# lose.
IN_BOOTH_CMD="./.cb-tests/inBooth--run-all-tests.sh"

# Decide here and pass the answer in, rather than letting the booth decide again
# from different inputs. The host is where the interesting signals live — whether
# this is CI, and whether the user asked either way — and the value is always
# explicit so the in-booth script never has to guess.
#
# Opt-out, not opt-in: the emulator test runs on a machine that can afford it.
# /dev/kvm is checked on the host because the booth is configured with
# `--device /dev/kvm`, so what the host has is what the booth gets.
EMULATOR=1
case "${CB_ANDROID_EMULATOR_TEST:-}" in
    1|true|yes|on)  ;;
    0|false|no|off) EMULATOR=0 ;;
    *)
        if [[ -n "${CI:-}" ]]; then
            EMULATOR=0
        elif [[ ! -c /dev/kvm || ! -r /dev/kvm || ! -w /dev/kvm ]]; then
            EMULATOR=0
        fi
        ;;
esac
IN_BOOTH_CMD="CB_ANDROID_EMULATOR_TEST=$EMULATOR $IN_BOOTH_CMD"

"$BOOTH" --port "${CB_PORT:-50411}" -- "$IN_BOOTH_CMD" 2>&1 | tee "$0.out"
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
