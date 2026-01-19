#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: Duplicate ports from CLI and config.toml are deduplicated

set -euo pipefail

source ../../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

# Run with config that has 8080 and 3000, plus CLI adds 8080 again (duplicate) and 5000 (new)
ACTUAL=$(../../../coding-booth --config test--config.toml --dryrun -p 8080:8080 -p 5000:5000 2>&1 | strip_ansi)

# Test 1: Check that all unique ports are present in DinD sidecar (no duplicates)
# Expected: -p 10000:10000 -p 8080:8080 -p 3000:3000 -p 5000:5000
if echo "$ACTUAL" | grep "docker:dind" | grep -q "\-p 10000:10000 -p 8080:8080 -p 3000:3000 -p 5000:5000"; then
    print_test_result "true" "$0" "1" "All unique ports present in correct order"
else
    print_test_result "false" "$0" "1" "All unique ports present in correct order"
    echo "Expected: -p 10000:10000 -p 8080:8080 -p 3000:3000 -p 5000:5000"
    echo "Actual DinD sidecar command:"
    echo "$ACTUAL" | grep "docker:dind" || echo "(docker:dind line not found)"
    exit 1
fi

# Test 2: Check that 8080 appears exactly once in the DinD sidecar command (deduplicated)
DIND_LINE=$(echo "$ACTUAL" | grep "docker:dind")
COUNT_8080=$(echo "$DIND_LINE" | grep -o "\-p 8080:8080" | wc -l)
if [ "$COUNT_8080" -eq 1 ]; then
    print_test_result "true" "$0" "2" "Port 8080:8080 appears exactly once (deduplicated)"
else
    print_test_result "false" "$0" "2" "Port 8080:8080 appears exactly once (deduplicated)"
    echo "Expected count: 1, Actual count: $COUNT_8080"
    exit 1
fi
