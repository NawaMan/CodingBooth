#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

passed=0
failed=0
failed_tests=()

for test_script in "$SCRIPT_DIR"/inBooth-test[0-9][0-9][0-9]-*.sh; do
    if [[ ! -f "$test_script" ]]; then
        continue
    fi

    test_name="$(basename "$test_script")"
    echo "----------------------------------------"
    echo "Running: $test_name"
    echo "----------------------------------------"

    if bash "$test_script"; then
        echo ">>> PASSED: $test_name"
        ((passed++))
    else
        echo ">>> FAILED: $test_name"
        ((failed++))
        failed_tests+=("$test_name")
    fi
    echo ""
done

echo "========================================"
echo "TEST SUMMARY"
echo "========================================"
echo "Passed: $passed"
echo "Failed: $failed"
echo "Total:  $((passed + failed))"

if [[ ${#failed_tests[@]} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for t in "${failed_tests[@]}"; do
        echo "  - $t"
    done
    exit 1
else
    echo ""
    echo "All tests passed!"
    exit 0
fi
