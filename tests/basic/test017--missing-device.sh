#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a --device run-arg for hardware this host does not have must not stop the
# booth from starting.
#
# `docker run --device /dev/nope` fails before the container is created ("error
# gathering device information ... no such file or directory"). Since run-args are
# emitted unconditionally by whatever template was selected, and device presence is
# a property of the host rather than the project, that would let a selected
# template break the booth on someone else's machine. FilterMissingDevices drops
# the flag with a warning instead — the same contract FilterMissingVolumeMounts
# applies to bind mounts.
#
# This is the integration half; the unit tests in pkg/booth/devices_test.go cover
# the parsing and the partial-drop cases.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

MISSING_DEVICE="/dev/cb-definitely-not-a-device"

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/config.toml" <<EOF
run-args = ["--device", "${MISSING_DEVICE}"]
EOF

FAILED=0

# The booth must start and run the command despite the impossible device.
OUTPUT=$(run_coding_booth --silence-build --code "$TEST_DIR" --variant base -- \
    bash -c 'echo CB_BOOTH_STARTED' 2>&1) || true

if echo "$OUTPUT" | grep -q "CB_BOOTH_STARTED"; then
    print_test_result "true" "$0" "017" "Booth starts despite a --device the host does not have"
else
    print_test_result "false" "$0" "017" "Booth should start despite a --device the host does not have"
    echo "  Output: $OUTPUT"
    FAILED=$((FAILED + 1))
fi

# Silently dropping it would be worse than failing: the user needs to know why the
# hardware they asked for is not there.
if echo "$OUTPUT" | grep -q "Skipping device"; then
    print_test_result "true" "$0" "017" "Dropping the device is reported, not silent"
else
    print_test_result "false" "$0" "017" "Dropping the device should be reported"
    echo "  Output: $OUTPUT"
    FAILED=$((FAILED + 1))
fi

# And it must not have reached Docker, which is what the whole filter is about.
if echo "$OUTPUT" | grep -qi "error gathering device information"; then
    print_test_result "false" "$0" "017" "The missing device should never reach docker run"
    echo "  Output: $OUTPUT"
    FAILED=$((FAILED + 1))
else
    print_test_result "true" "$0" "017" "The missing device never reaches docker run"
fi

exit $FAILED
