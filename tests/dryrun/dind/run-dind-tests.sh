#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Each test runs through run_test_script, which fails a test that bash 3.2 let
# exit 0 after it died on an unbound variable (see run-test-script--source.sh).
source "$(dirname "${BASH_SOURCE[0]}")/../../run-test-script--source.sh"

failed=0
failed_tests=()
total_tests=0

for f in test0*.sh ; do
    echo "$f"
    total_tests=$((total_tests + 1))

    if ! run_test_script ./"$f"; then
        failed=1
        failed_tests+=("$f")
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

exit $failed
