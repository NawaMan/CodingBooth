#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


failed=0
failed_tests=()
total_tests=0

# Retry a failed test once, immediately.
#
# The retry cannot be conditioned on recognising a transient: tests call the
# booth with --silence-build and 2>/dev/null, so an archive 503 reaches this
# runner as nothing but an empty diff. A test that only passes on the second
# attempt is still reported at the end, so this tolerates flakiness without
# hiding it.
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

# Run tests in subdirectories
for subdir in */ ; do
    if [ -d "$subdir" ] && [ -f "${subdir}run-"*"-tests.sh" ]; then
        echo "--- Running tests in $subdir ---"
        pushd "$subdir" > /dev/null
        for f in test0*.sh ; do
            if [ -f "$f" ]; then
                echo "$f"
                total_tests=$((total_tests + 1))

                if ! ./"$f"; then
                    echo "⚠️  FAILED: ${subdir}$f — retrying once"
                    retried_tests+=("${subdir}$f")
                    if ./"$f"; then
                        echo "✅ PASSED after retry: ${subdir}$f"
                    else
                        failed=1
                        failed_tests+=("${subdir}$f")
                    fi
                fi
                echo ""
            fi
        done
        popd > /dev/null
    fi
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
