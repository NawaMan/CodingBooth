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

# Test 1-10: Show a template by name
booth template show go > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^Go (go)"                "show: header line"
assert-contains "$tmpfile" "^Category:.*languages"   "show: category"
assert-contains "$tmpfile" "^Description:.*Go tool"  "show: description"
assert-contains "$tmpfile" "Provides a complete Go"  "show: long description"
assert-contains "$tmpfile" "^Parameters:"            "show: parameters section"
assert-contains "$tmpfile" "GO_VERSION"              "show: GO_VERSION parameter"
assert-contains "$tmpfile" "^Extensions:"            "show: extensions section"
assert-contains "$tmpfile" "^Tags:.*golang.*backend" "show: tags"
assert-contains "$tmpfile" "^Requires: (none)"       "show: requires (none)"
assert-contains "$tmpfile" "^Changes:"               "show: changes section"

# Test 11-13: Show extension with parent+ext syntax
booth template show python+uv > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^uv (uv)"               "show: python+uv header"
assert-contains "$tmpfile" "^Auto-select: no"        "show: python+uv auto-select"
assert-contains "$tmpfile" "^Changes:"               "show: python+uv changes"

# Test 14: Show with --detail shows file contents
booth template show python+uv --detail > "$tmpfile" 2>&1
assert-contains "$tmpfile" "    |"                   "show --detail: content lines"

# Test 15: Show template with requires
booth template show kotlin > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^Requires: java"         "show: kotlin requires java"

# Test 16: Show auto-select extension
booth template show go+vscode-ext > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^Auto-select: yes"       "show: auto-select yes"

# Test 17: Show unknown template gives error
booth template show nonexistent > "$tmpfile" 2>&1
assert-contains "$tmpfile" 'template "nonexistent" not found' "show: unknown template error"

# Test 18: Show unknown extension gives error
booth template show go+nonexistent > "$tmpfile" 2>&1
assert-contains "$tmpfile" 'extension "nonexistent" not found' "show: unknown extension error"

finally
