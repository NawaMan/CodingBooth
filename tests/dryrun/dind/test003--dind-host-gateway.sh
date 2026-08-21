#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: with DinD, the host alias is set on the sidecar, never on the booth
#
# The booth borrows the sidecar's network namespace, and docker refuses
# --add-host on a container that does that ("conflicting options: custom
# host-to-IP mapping and the network mode"). Putting the flag on the booth
# would not merely lose host access -- the run would not start at all.

set -euo pipefail

source ../../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

ACTUAL=$(run_coding_booth --config test--config.toml --dryrun 2>&1 | strip_ansi)

# Test 1: the sidecar carries the alias
DIND_LINE=$(echo "$ACTUAL" | grep "docker:dind")
if echo "$DIND_LINE" | grep -q -- "--add-host host\.docker\.internal:host-gateway"; then
    print_test_result "true" "$0" "1" "DinD sidecar carries the host.docker.internal alias"
else
    print_test_result "false" "$0" "1" "DinD sidecar carries the host.docker.internal alias"
    echo "Expected to find: --add-host host.docker.internal:host-gateway"
    echo "Actual DinD sidecar command:"
    echo "$DIND_LINE" || echo "(docker:dind line not found)"
    exit 1
fi

# Test 2: the booth container does not -- see the header
BOOTH_CMD=$(echo "$ACTUAL" | sed -n '/Running booth in foreground/,/^docker.*stop/p' | grep -v "docker:dind")
if echo "$BOOTH_CMD" | grep -q -- "--add-host"; then
    print_test_result "false" "$0" "2" "Booth container has no --add-host (alias on sidecar only)"
    echo "Actual booth command:"
    echo "$BOOTH_CMD"
    exit 1
else
    print_test_result "true" "$0" "2" "Booth container has no --add-host (alias on sidecar only)"
fi

# Test 3: the booth is still told the name to use
if echo "$BOOTH_CMD" | grep -q "BOOTH_HOST_NAME=host\.docker\.internal"; then
    print_test_result "true" "$0" "3" "Booth is told the host name to dial"
else
    print_test_result "false" "$0" "3" "Booth is told the host name to dial"
    exit 1
fi
