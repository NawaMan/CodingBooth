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

# Test 1: ruby+repl-history creates .irb_history
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "ruby+repl-history"
assert_file "$prj/.booth/cache/home/coder/.irb_history" "ruby+repl-history creates .irb_history"

# Test 2: redis+cli-history creates .rediscli_history
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "redis+cli-history"
assert_file "$prj/.booth/cache/home/coder/.rediscli_history" "redis+cli-history creates .rediscli_history"

# Test 3: mongodb+cli-history creates .mongosh/.mount-this
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "mongodb+cli-history"
assert_file "$prj/.booth/cache/home/coder/.mongosh/.mount-this" "mongodb+cli-history creates .mongosh dir"

# Test 4: elixir+repl-history creates erlang-history/.mount-this
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "elixir+repl-history"
assert_file "$prj/.booth/cache/home/coder/.cache/erlang-history/.mount-this" "elixir+repl-history creates erlang-history dir"

# Test 5: php+repl-history creates psysh/.mount-this
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "php+repl-history"
assert_file "$prj/.booth/cache/home/coder/.config/psysh/.mount-this" "php+repl-history creates psysh dir"

# Test 6: codeserver+settings-cache creates code-server dir
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "codeserver+settings-cache"
assert_file "$prj/.booth/cache/home/coder/.local/share/code-server/.mount-this" "codeserver+settings-cache creates dir"

# Test 7: neovim+data-cache creates both nvim dirs
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "neovim+data-cache"
assert_file "$prj/.booth/cache/home/coder/.local/share/nvim/.mount-this" "neovim+data-cache creates share/nvim dir"
assert_file "$prj/.booth/cache/home/coder/.local/state/nvim/.mount-this" "neovim+data-cache creates state/nvim dir"

# Test 8: firefox+profile-cache creates .mozilla dir
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "firefox+profile-cache"
assert_file "$prj/.booth/cache/home/coder/.mozilla/.mount-this" "firefox+profile-cache creates .mozilla dir"

# Test 9: chromium+profile-cache creates .chrome-data dir (wrapper user-data-dir)
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "chromium+profile-cache"
assert_file "$prj/.booth/cache/home/coder/.chrome-data/.mount-this" "chromium+profile-cache creates .chrome-data dir"

# Test 10: google-chrome+profile-cache creates .chrome-data dir
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "google-chrome+profile-cache"
assert_file "$prj/.booth/cache/home/coder/.chrome-data/.mount-this" "google-chrome+profile-cache creates .chrome-data dir"

# Test 11: google-chrome+bookmarks-shared creates shared Default/ dir (rename-safe)
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "google-chrome+bookmarks-shared"
assert_file "$prj/.booth/shared/home/coder/.chrome-data/Default/.mount-this" "google-chrome+bookmarks-shared creates Default dir"

# Test 12: chromium+bookmarks-shared creates shared Default/ dir
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "chromium+bookmarks-shared"
assert_file "$prj/.booth/shared/home/coder/.chrome-data/Default/.mount-this" "chromium+bookmarks-shared creates Default dir"

# Test 12b: firefox+bookmarks-shared creates shared firefox/ dir
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "firefox+bookmarks-shared"
assert_file "$prj/.booth/shared/home/coder/.mozilla/firefox/.mount-this" "firefox+bookmarks-shared creates firefox dir"

# Test 12c: chrome settings/extensions shared (not cache)
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "google-chrome+settings-shared+extensions-shared"
assert_file "$prj/.booth/shared/home/coder/.chrome-data/Default/.mount-this" "chrome+settings-shared creates Default"
assert_file "$prj/.booth/shared/home/coder/.chrome-data/Default/Extensions/.mount-this" "chrome+extensions-shared creates Extensions"
# Must not create cache entries for these
if [ -d "$prj/.booth/cache/home/coder/.chrome-data" ]; then
  FAIL_COUNT=$((FAIL_COUNT + 1)); TEST_COUNT=$((TEST_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: chrome settings/ext must not use cache ........ \033[31mFAILED\033[0m"
  FAIL_TESTS+=("chrome settings/ext must not use cache")
else
  TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: chrome settings/ext must not use cache ........ \033[32mPASSED\033[0m"
fi

# Test 12d: firefox settings/extensions shared (not cache)
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "firefox+settings-shared+extensions-shared"
assert_file "$prj/.booth/shared/home/coder/.mozilla/firefox/.mount-this" "firefox+settings-shared creates firefox dir"
if [ -d "$prj/.booth/cache/home/coder/.mozilla" ]; then
  FAIL_COUNT=$((FAIL_COUNT + 1)); TEST_COUNT=$((TEST_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: firefox settings/ext must not use cache ....... \033[31mFAILED\033[0m"
  FAIL_TESTS+=("firefox settings/ext must not use cache")
else
  TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: firefox settings/ext must not use cache ....... \033[32mPASSED\033[0m"
fi

# Test 13: codeserver+settings-shared creates shared settings.json
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "codeserver+settings-shared"
assert_file "$prj/.booth/shared/home/coder/.local/share/code-server/User/settings.json" "codeserver+settings-shared creates settings.json"

# Test 14: dbeaver+connections-shared creates shared data-sources.json
run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select "dbeaver+connections-shared"
assert_file "$prj/.booth/shared/home/coder/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json" "dbeaver+connections-shared creates data-sources.json"

finally
