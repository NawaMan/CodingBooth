#!/bin/bash
# A selection is a shallow tree: templates at the root, extensions under them.
# --add-select and --remove-select address its nodes by path, and apply in the
# order they are given. A recipe is expanded when it is used: the header records
# the nodes it selected, never "@name".
source "$(dirname "$0")/../test-helpers--source.sh"

begin
boothfile="$prj/.booth/Boothfile"
warning="$prj/warning.txt"

function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }
function check() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="${1}" message="${2}" width=64
    local label="${message} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad
    pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    local test="Test ${TEST_COUNT}: ${label}"
    echo -n "${test}${pad} "
    if [[ "${ok}" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}
header="# Configured by: booth config --no-tui --overwrite --select"

# ---------------------------------------------------------------------------
# An extension path names the extension under one template only, though
# python carries an extension of the same name.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "go+vscode-ext/python+vscode-ext"
run booth config $prj --no-tui --overwrite --remove-select go+vscode-ext
has "$boothfile" "$header go/python+vscode-ext"
check $? "go+vscode-ext is removed, python+vscode-ext is kept"

# ---------------------------------------------------------------------------
# Adding through a path changes only the node at its end: go keeps its pin.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go:1.24.13+linter"
run booth config $prj --no-tui --overwrite --add-select go+go-pkg
has "$boothfile" "$header go:1.24.13+linter+go-pkg"
check $? "--add-select go+go-pkg leaves go's version and linter alone"
has "$boothfile" "arg GO_VERSION=1.24.13"
check $? "and the Boothfile keeps GO_VERSION=1.24.13"

# ---------------------------------------------------------------------------
# An empty param list puts a node back to its defaults — also past a pin the
# Boothfile alone still holds.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --add-select "go:"
has "$boothfile" "$header go+linter+go-pkg"
check $? "--add-select go: drops the pin from the header"
if has "$boothfile" "arg GO_VERSION=1.24.13"; then ok=1; else ok=0; fi
check $ok "and from the Boothfile's GO_VERSION"

# ---------------------------------------------------------------------------
# Adds and removes apply in command-line order: the later write wins.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go"
run booth config $prj --no-tui --overwrite --add-select go+linter --remove-select go+linter
has "$boothfile" "$header go"
check $? "add then remove leaves go without linter"
run booth config $prj --no-tui --overwrite --remove-select go --add-select go+linter
has "$boothfile" "$header go+linter"
check $? "remove then add brings go back with linter"

# A template removed and added back without params comes back at its defaults,
# not at the pin its old Boothfile carried.
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go:1.24.13"
run booth config $prj --no-tui --overwrite --remove-select go --add-select go
if has "$boothfile" "arg GO_VERSION=1.24.13"; then ok=1; else ok=0; fi
check $ok "go removed and re-added drops the old GO_VERSION pin"

# ---------------------------------------------------------------------------
# An exclusion is a node too: it can be removed by its path.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "python~vscode-ext"
run booth config $prj --no-tui --overwrite --remove-select "python~vscode-ext"
has "$boothfile" "$header python"
check $? "--remove-select python~vscode-ext drops the exclusion"

# ---------------------------------------------------------------------------
# A recipe expands when it is used; the header records its nodes.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
mkdir -p "$prj/.booth/recipes"
printf 'go+linter # the stack\npython\n' > "$prj/.booth/recipes/web.recipe"
run booth config $prj --no-tui --select @web --select rust
has "$boothfile" "$header go+linter/python/rust"
check $? "--select @web --select rust records the recipe's nodes"

# The booth no longer depends on the recipe file.
printf 'java\n' > "$prj/.booth/recipes/web.recipe"
run booth config $prj --no-tui --overwrite
has "$boothfile" "$header go+linter/python/rust"
check $? "a changed recipe does not reach the booth on reconfigure"

run booth config $prj --no-tui --overwrite --add-select @web
has "$boothfile" "$header go+linter/python/rust/java"
check $? "--add-select @web adds what the recipe holds now"

cp "$boothfile" "$prj/Boothfile.before"
if booth config $prj --no-tui --overwrite --remove-select @web 2> "$warning" >/dev/null; then ok=1; else ok=0; fi
check $ok "--remove-select @web is refused"
has "$warning" 'is a recipe, not a node'
check $? "and the error says a recipe is not a node"
cmp -s "$boothfile" "$prj/Boothfile.before"
check $? "and the booth was not rewritten"

# ---------------------------------------------------------------------------
# A header written before this joined a recipe with the rest: "@web/rust".
# It is read back as the recipe plus rust, so the booth can be reconfigured.
# ---------------------------------------------------------------------------
printf 'go+linter\npython\n' > "$prj/.booth/recipes/web.recipe"
run booth config $prj --no-tui --overwrite --select @web/rust
run booth config $prj --no-tui --overwrite --add-select java
has "$boothfile" "$header go+linter/python/rust/java"
check $? "an old @web/rust header is rescued"

finally
