#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: claude-code+settings-cache creates .mount-this marker
run booth init new $prj --select "claude-code+settings-cache"
TEST_COUNT=$((TEST_COUNT + 1))
label="settings-cache creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.claude/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $prj/.booth/cache/home/coder/.claude/.mount-this to exist"
fi

# Test 2: .mount-this marker is empty (zero bytes)
TEST_COUNT=$((TEST_COUNT + 1))
label=".mount-this marker is empty "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
marker_size=$(stat -c%s "$prj/.booth/cache/home/coder/.claude/.mount-this" 2>/dev/null || echo "-1")
if [ "$marker_size" = "0" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: 0 bytes, FOUND: $marker_size"
fi

# Test 3: .gitignore contains cache/
gitignore="$prj/.booth/.gitignore"
TEST_COUNT=$((TEST_COUNT + 1))
label=".gitignore contains cache/ "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q "^cache/" "$gitignore" 2>/dev/null; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: 'cache/' in $gitignore"
fi

# Test 4: adjust preserves existing .mount-this (no-clobber)
echo "SHOULD_NOT_BE_OVERWRITTEN" > "$prj/.booth/cache/home/coder/.claude/.mount-this"
run booth init adjust $prj --select "claude-code+settings-cache"
TEST_COUNT=$((TEST_COUNT + 1))
label="adjust preserves existing .mount-this "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
content=$(cat "$prj/.booth/cache/home/coder/.claude/.mount-this" 2>/dev/null)
if [ "$content" = "SHOULD_NOT_BE_OVERWRITTEN" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: SHOULD_NOT_BE_OVERWRITTEN"
    echo "  FOUND   : $content"
fi

# Test 5: template without cache-dirs does NOT create cache/ directory
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go"
TEST_COUNT=$((TEST_COUNT + 1))
label="no cache/ for template without cache-dirs "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ ! -d "$prj/.booth/cache" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: cache/ directory should not exist for go template"
fi

finally
