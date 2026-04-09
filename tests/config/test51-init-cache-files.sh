#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: shell-history creates .bash_history cache file
run booth config $prj --no-tui --select "shell-history"
TEST_COUNT=$((TEST_COUNT + 1))
label="shell-history creates .bash_history "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.bash_history" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $prj/.booth/cache/home/coder/.bash_history to exist"
fi

# Test 2: shell-history creates .zsh_history cache file
TEST_COUNT=$((TEST_COUNT + 1))
label="shell-history creates .zsh_history "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.zsh_history" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $prj/.booth/cache/home/coder/.zsh_history to exist"
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

# Test 4: cache files are empty (zero bytes)
TEST_COUNT=$((TEST_COUNT + 1))
label="cache files are empty "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
bash_size=$(stat -c%s "$prj/.booth/cache/home/coder/.bash_history" 2>/dev/null || echo "-1")
zsh_size=$(stat -c%s "$prj/.booth/cache/home/coder/.zsh_history" 2>/dev/null || echo "-1")
if [ "$bash_size" = "0" ] && [ "$zsh_size" = "0" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: 0 bytes, FOUND: bash=$bash_size zsh=$zsh_size"
fi

# Test 5: adjust preserves existing cache files (no-clobber)
echo "EXISTING_HISTORY_LINE" > "$prj/.booth/cache/home/coder/.bash_history"
run booth config $prj --no-tui --overwrite --select "shell-history"
TEST_COUNT=$((TEST_COUNT + 1))
label="adjust preserves existing cache files "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
content=$(cat "$prj/.booth/cache/home/coder/.bash_history" 2>/dev/null)
if [ "$content" = "EXISTING_HISTORY_LINE" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: EXISTING_HISTORY_LINE"
    echo "  FOUND   : $content"
fi

# Test 6: python+repl-history creates .python_history
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "python+repl-history"
TEST_COUNT=$((TEST_COUNT + 1))
label="python+repl-history creates .python_history "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.python_history" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $prj/.booth/cache/home/coder/.python_history to exist"
fi

# Test 7: template without cache-files does NOT create cache/ directory
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go"
TEST_COUNT=$((TEST_COUNT + 1))
label="no cache/ for template without cache-files "
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
