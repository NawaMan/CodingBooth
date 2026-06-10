#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Setup/install script unit-test runner
# Runs the scripts in variants/base/setups/ directly with stubbed external
# commands, asserting the command lines they emit. These are fast, hermetic
# unit tests — they do NOT build a booth image.

failed=0
failed_tests=()
total_tests=0

for f in test--*.sh ; do
    if [ -f "$f" ]; then
        echo "$f"
        total_tests=$((total_tests + 1))

        if ! ./"$f"; then
            failed=1
            failed_tests+=("$f")
        fi
        echo ""
    fi
done

num_failed=${#failed_tests[@]}

if [ $failed -eq 0 ]; then
    echo "All $total_tests setups tests passed."
else
    echo "$num_failed out of $total_tests setups tests FAILED."
    echo "Failed tests:"
    for t in "${failed_tests[@]}"; do
        echo "  - $t"
    done
fi

exit $failed
