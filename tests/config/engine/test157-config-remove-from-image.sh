#!/bin/bash
# A top-level "~name" takes a tool the variant image ships back out of the
# booth: the Boothfile gains the template's remove step, after every install,
# and the selection header keeps "~name" so a reconfigure reproduces it. Only
# templates with a remove step can be removed, and only from a variant whose
# image has the tool.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
boothfile="$prj/.booth/Boothfile"
out="$prj/out.txt"

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
# ~glow emits glow's remove step after the go install, and is kept in the header.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "go/~glow"
has "$boothfile" "--select go/~glow"
check $? "the header keeps ~glow"
has "$boothfile" "run rm -f /usr/local/bin/glow"
check $? "the Boothfile carries glow's remove step"
! has "$boothfile" "setup glow"
check $? "a removed template is not installed"
setup_at=$(grep -n 'setup go-code-extension' "$boothfile" | cut -d: -f1)
remove_at=$(grep -n 'run rm -f /usr/local/bin/glow' "$boothfile" | cut -d: -f1)
[[ -n "$setup_at" && -n "$remove_at" && "$remove_at" -gt "$setup_at" ]]
check $? "the removal comes after every install"

# ---------------------------------------------------------------------------
# A reconfigure with no flags reproduces the removal from the header.
# ---------------------------------------------------------------------------
cp "$boothfile" "$prj/Boothfile.before"
run booth config $prj --no-tui --overwrite
cmp -s "$boothfile" "$prj/Boothfile.before"
check $? "reconfiguring from the header reproduces the Boothfile"

# ---------------------------------------------------------------------------
# --add-select '~ttt' adds a removal; ttt's step also sets EDITOR back to nano.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --add-select "~ttt"
has "$boothfile" "--select go/~glow/~ttt"
check $? "--add-select appends ~ttt to the selection"
has "$boothfile" "env EDITOR=nano"
check $? "removing ttt points EDITOR at nano"

# ---------------------------------------------------------------------------
# Selecting the template again replaces its removal.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --add-select "glow"
has "$boothfile" "--select go/glow/~ttt"
check $? "--add-select glow takes the place of ~glow"
has "$boothfile" "setup glow"
check $? "glow is installed again"

# ---------------------------------------------------------------------------
# Refused: a template with no remove step, one the variant does not ship, and
# a template both selected and removed. Nothing is written.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
booth config $prj --no-tui --select "~gnupg" > "$out" 2>&1
[[ $? -ne 0 ]] && has "$out" "cannot be removed"
check $? "~gnupg is refused: it has no remove step"

booth config $prj --no-tui --select "~firefox" > "$out" 2>&1
[[ $? -ne 0 ]] && has "$out" "not in the base image"
check $? "~firefox is refused on base: the image has no Firefox"

booth config $prj --no-tui --select "glow/~glow" > "$out" 2>&1
[[ $? -ne 0 ]] && has "$out" "both selected and removed"
check $? "selecting and removing glow at once is refused"

[[ ! -f "$boothfile" ]]
check $? "a refused selection writes nothing"

# ---------------------------------------------------------------------------
# ~firefox is accepted where the image ships Firefox.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --variant desktop-xfce --select "~firefox"
has "$boothfile" "apt-get purge -y firefox"
check $? "~firefox on desktop-xfce emits the purge"

finally
