#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

# lean (experimental): elan needs ELAN_HOME and its bin dir as image env, ahead of
# setup lean, so `booth exec` finds lean/lake without a login shell. The
# toolchain-file extension is auto-selected; mathlib-cache is opt-in, and only it
# mounts the host's ~/.cache/mathlib.

begin

boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"

# pass/fail line in the same format as assert-line, for checks it can't express
check() {
    local label="$1"; shift
    TEST_COUNT=$((TEST_COUNT + 1))
    local pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

line_of() { grep -n "^$1" "$boothfile" | head -1 | cut -d: -f1; }
env_before_setup() {
    local e s
    e="$(line_of 'env ELAN_HOME=')"; s="$(line_of 'setup lean ')"
    [[ -n "$e" && -n "$s" && "$e" -lt "$s" ]]
}
no_mathlib_mount() { ! grep -q 'mathlib' "$config" 2>/dev/null; }

# --- bare lean: catalog default, env, toolchain-file, no Mathlib mount ------
run booth config $prj --no-tui --select 'lean'
assert-line "$boothfile" "setup lean" " --version \${LEAN_VERSION}"     "lean adds setup lean --version"
assert-line "$boothfile" "arg LEAN_VERSION=" "$(template-default lean LEAN_VERSION)" \
                                                                       "LEAN_VERSION default is the catalog's"
assert-line "$boothfile" "env ELAN_HOME=" "/opt/elan"                  "lean sets ELAN_HOME as image env"
assert-line "$boothfile" "env PATH=" "/opt/elan/bin:\$PATH"            "lean puts elan's bin on PATH"
check "env ELAN_HOME comes before setup lean" env_before_setup
assert-line "$boothfile" "setup lean-toolchain-file" " /tmp/cb-lean-toolchain" \
                                                                       "lean auto-selects toolchain-file"
check "mathlib-cache is not selected by default" no_mathlib_mount

# --- pinned ----------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'lean:4.35.0'
assert-line "$boothfile" "arg LEAN_VERSION=" "4.35.0"                   "lean:4.35.0 pins LEAN_VERSION"

# --- mathlib-cache mounts the host's ~/.cache/mathlib ------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'lean+mathlib-cache'
assert-line "$config" "run-args = " \
    '["-v", "$HOME/.cache/mathlib:/home/coder/.cache/mathlib:create"]' "mathlib-cache mounts ~/.cache/mathlib"

# --- interact: LeanInteract after both Python and Lean -----------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'lean+interact'
assert-line "$boothfile" "setup lean-interact" " --version \${LEAN_INTERACT_VERSION}" "lean+interact adds setup lean-interact"
# Extension params are not in `booth template show`, so read the default from the file.
interact_default="$(sed -n '/^\[params.LEAN_INTERACT_VERSION\]/,/^default/s/^default = "\(.*\)"/\1/p' \
    "$_repo_root/templates/languages/lean/interact--extension.toml")"
assert-line "$boothfile" "arg LEAN_INTERACT_VERSION=" "$interact_default" \
                                                                       "LEAN_INTERACT_VERSION default is the catalog's"
interact_last() {
    local p l i
    p="$(line_of 'setup python ')"; l="$(line_of 'setup lean ')"; i="$(line_of 'setup lean-interact ')"
    [[ -n "$p" && -n "$l" && -n "$i" && "$p" -lt "$i" && "$l" -lt "$i" ]]
}
check "interact pulls in python; runs after python and lean" interact_last

# --- blueprint: leanblueprint after LaTeX and Python, both pulled in -------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'lean+blueprint'
assert-line "$boothfile" "setup lean-blueprint" " --version \${LEAN_BLUEPRINT_VERSION}" "lean+blueprint adds setup lean-blueprint"
blueprint_default="$(sed -n '/^\[params.LEAN_BLUEPRINT_VERSION\]/,/^default/s/^default = "\(.*\)"/\1/p' \
    "$_repo_root/templates/languages/lean/blueprint--extension.toml")"
assert-line "$boothfile" "arg LEAN_BLUEPRINT_VERSION=" "$blueprint_default" \
                                                                       "LEAN_BLUEPRINT_VERSION default is the catalog's"
blueprint_last() {
    local t p b
    t="$(line_of 'setup latex ')"; p="$(line_of 'setup python ')"; b="$(line_of 'setup lean-blueprint ')"
    [[ -n "$t" && -n "$p" && -n "$b" && "$t" -lt "$b" && "$p" -lt "$b" ]]
}
check "blueprint pulls in latex + python; runs after both" blueprint_last

# --- mcp: lean-lsp-mcp for agents; nvim: lean.nvim, pulling in neovim -------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'lean+mcp+nvim'
assert-line "$boothfile" "setup lean-lsp-mcp" " --version \${LEAN_LSP_MCP_VERSION}" "lean+mcp adds setup lean-lsp-mcp"
assert-line "$boothfile" "setup lean-nvim" " --version \${LEAN_NVIM_VERSION}"       "lean+nvim adds setup lean-nvim"
nvim_after_neovim() {
    local n l
    n="$(line_of 'setup neovim ')"; l="$(line_of 'setup lean-nvim ')"
    [[ -n "$n" && -n "$l" && "$n" -lt "$l" ]]
}
check "nvim pulls in neovim; lean.nvim installs after it" nvim_after_neovim

# --- VS Code extension is auto-selected (its script skips itself without code-server)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant codeserver --select 'lean'
assert-line "$boothfile" "setup lean-code-extension" "" "lean auto-selects its VS Code extension"

finally
