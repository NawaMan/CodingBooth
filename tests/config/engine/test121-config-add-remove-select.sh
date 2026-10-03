#!/bin/bash
# --add-select / --remove-select edit an existing booth's selection in place,
# instead of the plain --select's whole-selection replace. --add-select unions
# in template/extension names; --remove-select drops them, and can combine with
# --add-select in the same run to replace one template's params without
# restating anything else.
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

# ---------------------------------------------------------------------------
# --add-select adds a whole new template onto an existing selection.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "go/python"
run booth config $prj --no-tui --overwrite --add-select java
has "$boothfile" "# Configured by: booth config --no-tui --overwrite --select go/python/java"
check $? "java was added onto the existing selection"

# ---------------------------------------------------------------------------
# --add-select adds an extension to an already-selected template, rather than
# selecting that template a second time (which the resolver rejects outright).
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go/python"
run booth config $prj --no-tui --overwrite --add-select "go+linter"
has "$boothfile" "# Configured by: booth config --no-tui --overwrite --select go+linter/python"
check $? "the extension is merged onto the existing go, not selected twice"

# ---------------------------------------------------------------------------
# --remove-select drops a whole template, keeping the rest.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go/python/java"
run booth config $prj --no-tui --overwrite --remove-select python
has "$boothfile" "# Configured by: booth config --no-tui --overwrite --select go/java"
check $? "python was removed, go and java survive"

# ---------------------------------------------------------------------------
# --remove-select drops just an extension, keeping its template.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go+linter+go-pkg/python"
run booth config $prj --no-tui --overwrite --remove-select linter
has "$boothfile" "# Configured by: booth config --no-tui --overwrite --select go+go-pkg/python"
check $? "the linter extension was removed, go-pkg and go and python survive"

# ---------------------------------------------------------------------------
# --remove-select and --add-select combine in one run: replace a template's
# params by removing it, then re-adding it with the new ones.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go:1.24.13/python"
run booth config $prj --no-tui --overwrite --remove-select go --add-select "go:1.25.7"
# Removing "go" drops it from the list; adding it back appends it fresh at the
# end, same as typing it new — the point is the version changed, not the order.
has "$boothfile" "# Configured by: booth config --no-tui --overwrite --select python/go:1.25.7"
check $? "go's version was replaced by remove+add in one run"

# ---------------------------------------------------------------------------
# --remove-select for a name that matches nothing is a no-op with a warning,
# not an error.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go"
booth config $prj --no-tui --overwrite --remove-select rust 2> "$warning" >/dev/null
has "$boothfile" "# Configured by: booth config --no-tui --overwrite --select go"
check $? "the selection is unchanged"
has "$warning" 'did not match anything'
check $? "a --remove-select name matching nothing only warns"

# ---------------------------------------------------------------------------
# --select combined with --remove-select is refused: --select already
# discards the whole baseline, so there is nothing left for --remove-select
# to act on.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go"
if run booth config $prj --no-tui --overwrite --select "python" --remove-select go; then ok=1; else ok=0; fi
check $ok "combining --select with --remove-select is refused"

finally
