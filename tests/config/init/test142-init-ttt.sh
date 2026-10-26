#!/bin/bash
# ttt: setup line, version pin, config-shared mount; +lsp and +theme come selected
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

# --- bare ttt: latest --------------------------------------------------------
run booth config $prj --no-tui --select 'ttt'
assert-line "$boothfile" "setup ttt" " --version \${TTT_VERSION}" "ttt adds setup ttt --version"
assert-line "$boothfile" "arg TTT_VERSION=" "$(template-default ttt TTT_VERSION)" "TTT_VERSION default is the catalog's"

# --- +lsp and +theme come with bare ttt --------------------------------------
startup="$prj/.booth/startups/74-ttt-theme--startup.sh"
assert-line "$boothfile" "setup ttt-lsp" '' "ttt auto-selects ttt+lsp"
assert-line "$boothfile" "arg TTT_THEME=" "$(template-default ttt+theme TTT_THEME)" "TTT_THEME default is the catalog's"
assert-line "$boothfile" "arg TTT_BORDER_STYLE=" "$(template-default ttt+theme TTT_BORDER_STYLE)" "TTT_BORDER_STYLE default is the catalog's"
TEST_COUNT=$((TEST_COUNT + 1))
label="ttt+theme seeds theme and border only where unset "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -qF '.theme //= $theme | .editor.borderStyle //= $border' "$startup" 2>/dev/null; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  startup: $(ls "$startup" 2>&1)"
fi

# --- a theme and border pin ---------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'ttt+theme:dracula,double'
assert-line "$boothfile" "arg TTT_THEME=" "dracula" "ttt+theme:dracula pins TTT_THEME"
assert-line "$boothfile" "arg TTT_BORDER_STYLE=" "double" "ttt+theme:dracula,double pins the border"

# --- ~ drops both ----------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'ttt~lsp~theme'
TEST_COUNT=$((TEST_COUNT + 1))
label="ttt~lsp~theme drops both "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if ! grep -qE '^(setup ttt-lsp|arg TTT_THEME=)' "$boothfile" && [ ! -e "$startup" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    grep -E '^(setup ttt-lsp|arg TTT_THEME=)' "$boothfile"; ls "$startup" 2>/dev/null
fi

# --- pinned ------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'ttt:1.8.0'
assert-line "$boothfile" "arg TTT_VERSION=" "1.8.0" "ttt:1.8.0 pins TTT_VERSION"

# --- config-shared creates the shared mount marker ---------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'ttt+config-shared'
TEST_COUNT=$((TEST_COUNT + 1))
label="config-shared creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/shared/home/coder/.config/ttt/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/shared/home/coder/.config/ttt/.mount-this"
fi

finally
