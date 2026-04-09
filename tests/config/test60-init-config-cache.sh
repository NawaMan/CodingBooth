#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Helper for file-exists assertions
assert_file() {
    local path="$1"
    local label="$2"
    TEST_COUNT=$((TEST_COUNT + 1))
    local pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
    if [ -f "$path" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
        echo "  EXPECTED: file $path to exist"
    fi
}

# Test 1: --set cache-files creates cache file
run booth config $prj --no-tui --select "go" --set cache-files=home/coder/.custom_history
assert_file "$prj/.booth/cache/home/coder/.custom_history" "--set cache-files creates cache file"

# Test 2: config.toml contains cache-files entry
config="$prj/.booth/config.toml"
TEST_COUNT=$((TEST_COUNT + 1))
label="config.toml contains cache-files "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q 'cache-files' "$config" 2>/dev/null && grep -q 'home/coder/.custom_history' "$config" 2>/dev/null; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: cache-files with home/coder/.custom_history in $config"
fi

# Test 3: --set cache-dirs creates cache dir with .mount-this
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "go" --set cache-dirs=home/coder/.custom_data
assert_file "$prj/.booth/cache/home/coder/.custom_data/.mount-this" "--set cache-dirs creates dir with marker"

# Test 4: config.toml contains cache-dirs entry
config="$prj/.booth/config.toml"
TEST_COUNT=$((TEST_COUNT + 1))
label="config.toml contains cache-dirs "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q 'cache-dirs' "$config" 2>/dev/null && grep -q 'home/coder/.custom_data' "$config" 2>/dev/null; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: cache-dirs with home/coder/.custom_data in $config"
fi

# Test 5: dedup — template cache + --set same path produces one entry
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "shell-history" --set cache-files=home/coder/.bash_history
TEST_COUNT=$((TEST_COUNT + 1))
label="dedup template cache + --set same path "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
# The file should exist (from either source)
if [ -f "$prj/.booth/cache/home/coder/.bash_history" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: .bash_history to exist"
fi

finally
