#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


failed=0
failed_tests=()
total_tests=0

if ! command -v docker >/dev/null 2>&1; then
    echo "SKIP: Docker is not installed or not in PATH"
    exit 0
fi
if ! docker info >/dev/null 2>&1; then
    echo "SKIP: Docker daemon is not accessible (permission or not running)"
    exit 0
fi

# Retry a failed test once, immediately.
#
# A suite this long should not be lost to a transient — an archive 503, a
# registry blip — and the retry cannot be conditioned on *recognising* one:
# tests call the booth with --silence-build and 2>/dev/null, so the evidence
# never reaches this runner. test-boothfile-apt-snapshot failed exactly that
# way, with eight "Service Unavailable" lines in the diagnostic trace and
# nothing but an empty "Actual output:" here.
#
# A test that only passes on the second attempt is still reported at the end, so
# this buys tolerance of flakiness without hiding it.
retried_tests=()

for f in test0*.sh ; do
    echo "$f"
    total_tests=$((total_tests + 1))

    if ! ./"$f"; then
        echo "⚠️  FAILED: $f — retrying once"
        retried_tests+=("$f")
        if ./"$f"; then
            echo "✅ PASSED after retry: $f"
        else
            failed=1
            failed_tests+=("$f")
        fi
    fi
    echo ""
done

num_failed=${#failed_tests[@]}

if [ $failed -eq 0 ]; then
    echo "All $total_tests tests passed."
else
    echo "$num_failed out of $total_tests tests FAILED."
    echo "Failed tests:"
    for t in "${failed_tests[@]}"; do
        echo "  - $t"
    done
fi

# A pass that needed a second attempt is still a flake. Report it, or retrying
# quietly converts a real intermittent fault into a green suite.
if [ ${#retried_tests[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Retried after a first-attempt failure: ${#retried_tests[@]}"
    for t in "${retried_tests[@]}"; do
        echo "  - $t"
    done
fi

exit $failed
