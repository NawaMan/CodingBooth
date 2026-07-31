#!/bin/bash
# Config generation for Cursor + GitHub CLI templates and extensions.
source "$(dirname "$0")/test-helpers--source.sh"

begin

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
# Cursor — parent + auto credential extension
#
# Cursor's download URLs embed a build commit, so the knob is a release *track*
# rather than a version. That is why this template alone carries CURSOR_TRACK.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "cursor"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg CURSOR_TRACK=' 'stable'                    "cursor default track is stable"
assert-line "$boothfile" 'setup cursor ' '--track ${CURSOR_TRACK}'       "Boothfile uses cursor param reference"

config="$prj/.booth/config.toml"
# Cursor is a VS Code fork: the sign-in lives under the editor config dir, not
# in a single credential file, so all three host layouts are seeded.
has "$config" '"~/.config/Cursor:/etc/cb-home-seed/.config/Cursor:ro"'   ; check $? "cursor seeds Linux config dir"
has "$config" '"~/Library/Application Support/Cursor:/etc/cb-home-seed/.config/Cursor:ro"' ; check $? "cursor seeds macOS config dir"
has "$config" '"~/AppData/Roaming/Cursor:/etc/cb-home-seed/.config/Cursor:ro"'              ; check $? "cursor seeds Windows config dir"
has "$config" '"~/.cursor:/etc/cb-home-seed/.cursor:ro"'                ; check $? "cursor seeds CLI state dir"

# Pin the other track
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "cursor:latest"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg CURSOR_TRACK=' 'latest'                    "cursor custom track is latest"

# ---------------------------------------------------------------------------
# GitHub CLI — version knob
# ---------------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "gh"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GH_VERSION=' 'latest'                      "gh default version is latest"
assert-line "$boothfile" 'setup gh ' '--version ${GH_VERSION}'           "Boothfile uses gh param reference"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "gh:2.97.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GH_VERSION=' '2.97.0'                      "gh custom version is 2.97.0"

# ---------------------------------------------------------------------------
# gh-copilot pulls gh in via `requires`, and must NOT emit its own `setup gh`.
# A bare second `setup gh` would re-install the CLI unpinned, silently undoing
# whatever GH_VERSION resolved to on the line above it.
# ---------------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "gh-copilot"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'setup gh ' '--version ${GH_VERSION}'           "gh-copilot pulls in the pinned gh"
has "$boothfile" 'setup gh-copilot'                                     ; check $? "gh-copilot emits its own setup"
[[ "$(grep -c '^setup gh$' "$boothfile")" == "0" ]]
check $? "gh-copilot does not re-install gh unpinned"

# Pinning through gh-copilot still reaches the gh setup line.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "gh:2.96.0/gh-copilot"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GH_VERSION=' '2.96.0'                      "gh pin survives alongside gh-copilot"
[[ "$(grep -c '^setup gh$' "$boothfile")" == "0" ]]
check $? "still no unpinned gh alongside a pin"

finally
