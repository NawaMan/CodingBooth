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

# Helper: assert that a pattern does NOT exist in the file
function assert-not-contains() {
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
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"
        echo "  EXPECTED: pattern '${PATTERN}' to NOT be found"
        echo "  FOUND   : $(grep "$PATTERN" "$FILE" | head -1)"
    else
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    fi
}

# Capture `booth template list` output
booth template list > "$tmpfile" 2>&1

# Test 1: Category headers are present
assert-contains "$tmpfile" "^Languages"              "list: Languages category header"

# Test 2: Primary template names appear
assert-contains "$tmpfile" "^  go "                  "list: go template appears"

# Test 3: Template has description
assert-contains "$tmpfile" "Go toolchain"            "list: go has description"

# Test 4: Non-auto extension appears in list
assert-contains "$tmpfile" "    + linter"            "list: linter extension appears"

# Test 5: Auto-select extension shown with * marker
assert-contains "$tmpfile" "    + vscode-ext\*"      "list: auto-select vscode-ext shown with *"

# Test 6: Footer hint for --full
assert-contains "$tmpfile" "^Use --full"             "list: --full hint in footer"

# Test 7: Footer hint for show command
assert-contains "$tmpfile" "template show"           "list: show hint in footer"

# Test 8: Non-primary templates hidden by default
assert-not-contains "$tmpfile" "^  kotlin"           "list: non-primary kotlin hidden"
assert-not-contains "$tmpfile" "^  julia"            "list: non-primary julia hidden"
assert-not-contains "$tmpfile" "^  opencode"         "list: non-primary opencode hidden"

# Test 8b: curated Popular set is what the default list shows
assert-contains "$tmpfile" "^  sqlite "              "list: sqlite is popular"
assert-contains "$tmpfile" "^  lazygit "             "list: lazygit is popular"
assert-contains "$tmpfile" "^  neovim "              "list: neovim is popular"
assert-contains "$tmpfile" "^Middlewares"            "list: Middlewares category (has sqlite)"
assert-not-contains "$tmpfile" "^Browsers"           "list: Browsers is not a category"
assert-not-contains "$tmpfile" "^Desktop"            "list: Desktop has no popular templates"

# Test 9: --full shows non-primary templates
booth template list --full > "$tmpfile" 2>&1
assert-contains "$tmpfile" "^  kotlin"               "list --full: kotlin appears"

# Test 10: --full shows more categories
assert-contains "$tmpfile" "^Middlewares"            "list --full: Middlewares category"
assert-contains "$tmpfile" "^Desktop"                "list --full: Desktop category (browsers live here)"
assert-not-contains "$tmpfile" "^Databases"          "list --full: Databases renamed to Middlewares"
assert-not-contains "$tmpfile" "^Browsers"           "list --full: Browsers folded into Desktop"

# Test 11: AI Tools sits immediately after Tools
tools_line=$(grep -n "^Tools$" "$tmpfile" | head -1 | cut -d: -f1)
ai_line=$(grep -n "^AI Tools$" "$tmpfile" | head -1 | cut -d: -f1)
ides_line=$(grep -n "^IDEs$" "$tmpfile" | head -1 | cut -d: -f1)
TEST_COUNT=$((TEST_COUNT + 1))
label="list --full: AI Tools follows Tools "
pad_len=$((64 - ${#label}))
if (( pad_len < 3 )); then pad_len=3; fi
pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [[ -n "$tools_line" && -n "$ai_line" && -n "$ides_line" ]] &&
   (( tools_line < ai_line && ai_line < ides_line )); then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  Tools=$tools_line AI Tools=$ai_line IDEs=$ides_line"
fi

finally
