#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: DinD ports from config.toml are passed to the sidecar container

set -euo pipefail

source ../../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

# Run with config that has multiple ports
ACTUAL=$(../../../coding-booth --config test--config.toml --dryrun 2>&1 | strip_ansi)

# Test 1: Check that all ports are in the DinD sidecar command (docker:dind line)
if echo "$ACTUAL" | grep "docker:dind" | grep -q "\-p 10000:10000 -p 8080:8080 -p 3000:3000"; then
    print_test_result "true" "$0" "1" "All ports (10000, 8080, 3000) passed to DinD sidecar"
else
    print_test_result "false" "$0" "1" "All ports (10000, 8080, 3000) passed to DinD sidecar"
    echo "Expected to find: -p 10000:10000 -p 8080:8080 -p 3000:3000"
    echo "Actual DinD sidecar command:"
    echo "$ACTUAL" | grep "docker:dind" || echo "(docker:dind line not found)"
    exit 1
fi

# Test 2: Check that the booth container uses --network container:
if echo "$ACTUAL" | grep -q "\-\-network container:"; then
    print_test_result "true" "$0" "2" "Booth container uses container network mode"
else
    print_test_result "false" "$0" "2" "Booth container uses container network mode"
    exit 1
fi

# Test 3: Check that the booth container does NOT have -p flags
# The booth container command comes after "Running booth in foreground" and does NOT contain docker:dind
BOOTH_CMD=$(echo "$ACTUAL" | sed -n '/Running booth in foreground/,/^docker.*stop/p' | grep -v "docker:dind")
if echo "$BOOTH_CMD" | grep -q "^\s*-p [0-9]"; then
    print_test_result "false" "$0" "3" "Booth container has no -p flags (ports on sidecar only)"
    exit 1
else
    print_test_result "true" "$0" "3" "Booth container has no -p flags (ports on sidecar only)"
fi
