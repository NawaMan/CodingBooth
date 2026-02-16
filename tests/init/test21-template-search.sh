#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Helper: assert that a pattern exists in the file
function assert-contains() {
    local FILE="$1"
    local PATTERN="$2"
    local MESSAGE="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    local width=64
    local label="${MESSAGE} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    local test="Test ${TEST_COUNT}: ${label}"
    echo -n "${test}${pad} "

    if grep -q "$PATTERN" "$FILE"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"
        echo "  EXPECTED: pattern '${PATTERN}' to be found"
    fi
}

# Test 1: Search by template name
booth template search go > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^  go "                  "search: finds go by name"

# Test 2: Search shows matching extensions
booth template search linter > "$tmpfile" 2>&1
assert-contains "$tmpfile" "    + linter"            "search: finds linter extension"

# Test 3: Search is case-insensitive
booth template search GO > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^  go "                  "search: case-insensitive"

# Test 4: Search by tag
booth template search backend > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^  go "                  "search: tag 'backend' finds go"

# Test 5: Search with no results
booth template search zzzznotfound > "$tmpfile" 2>&1
assert-contains "$tmpfile" "No templates found"      "search: no results message"

# Test 6: Search by description word
booth template search toolchain > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^  go "                  "search: description word finds go"

# Test 7: Search shows auto-select extensions in results
booth template search "language support" > "$tmpfile" 2>&1
assert-contains "$tmpfile" "vscode-ext"              "search: auto-select ext in results"

finally
