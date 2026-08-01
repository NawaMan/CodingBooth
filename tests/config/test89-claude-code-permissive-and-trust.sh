#!/bin/bash
# The Accept Edits extension has to emit a permission set Claude Code accepts, and
# a trust stamp, because neither failure is visible from the generated file alone.
#
# A rule Claude Code rejects is worse than a rule that does nothing: the whole
# settings file is reported back as a "Settings Warning" the user must dismiss
# before the session starts, on every launch. `mcp__*` was exactly that — a glob
# is legal only in the tool position, after a literal mcp__<server>__ prefix — so
# an extension whose purpose is removing friction was adding a keystroke per run.
# There is no all-servers wildcard to replace it with, so the rule is simply gone
# and must not come back.
#
# The trust stamp is the other half. Claude Code gates a folder behind "Is this a
# project you trust?" before it will work in it, and that gate is not a permission
# rule — no allow entry can suppress it. It is project state in ~/.claude.json,
# which lives outside the ~/.claude/ settings cache and is therefore reseeded from
# the host every start, so the booth's own answer never survives. The startup
# segment stamps it, and steps aside when the file is a bind mount because then
# cache/ or shared/ owns it and already carries the answer across restarts.
source "$(dirname "$0")/test-helpers--source.sh"

begin
settings="$prj/.booth/home-seed/.claude/settings.json"
startup="$prj/.booth/startups/90-claude-code-auto-accept--startup.sh"

# has <file> <substring> — 0 when the file contains it
function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }

# check <0-if-ok> <message>
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

run booth config $prj --no-tui --overwrite --select "claude-code+auto-accept"

# ---------------------------------------------------------------------------
# The permission set still says what it is meant to say
# ---------------------------------------------------------------------------
has "$settings" '"Bash"'                    ; check $? "seeds the permissive allow list"
# Force push has four spellings and the guard only ever caught the long one, so
# each is pinned: `-f` ran unblocked in a booth (proved against `git reset --hard`
# as a control), and `+refspec` means the same thing with no flag at all. Both
# positions matter — a flag can trail the remote as easily as precede it.
has "$settings" '"Bash(git push --force*)"'   ; check $? "keeps --force denied"
has "$settings" '"Bash(git push * --force*)"' ; check $? "keeps trailing --force denied"
has "$settings" '"Bash(git push -f*)"'        ; check $? "keeps -f denied"
has "$settings" '"Bash(git push * -f*)"'      ; check $? "keeps trailing -f denied"
has "$settings" '"Bash(git push +*)"'         ; check $? "keeps +refspec force denied"
has "$settings" '"Bash(git push * +*)"'       ; check $? "keeps trailing +refspec force denied"

# The template carries this file as a TOML string, so nothing on the way out
# validates it as JSON. Drop the last entry of the allow or deny list by hand and
# the one above it keeps its comma, shipping a settings.json Claude Code cannot
# read — which is how removing the curl-pipe rules nearly went out. Full parse
# where jq exists; the trailing-comma check is the portable floor, and it is the
# failure hand-edits actually produce.
function settings_is_valid_json() {
    if command -v jq >/dev/null 2>&1; then
        jq -e . "$settings" >/dev/null 2>&1
    else
        ! tr -d ' \n\t' < "$settings" | grep -q ',[]}]'
    fi
}
settings_is_valid_json ; check $? "seeded settings.json is valid JSON"

# ---------------------------------------------------------------------------
# ... without the rule Claude Code rejects
# ---------------------------------------------------------------------------
! has "$settings" '"mcp__*"' ; check $? "no bare mcp__* wildcard in the seeded allow list"

# Repo-wide: the rule had been hand-copied into two other settings files — a blog
# booth and the elixir example — so assert on every checked-in copy, not only the
# one this test generates. Anchored to a whole line so that prose mentioning the
# rule (this file, the template's own comment, the CHANGELOG) is not a match.
#
# Scans git's index rather than walking the directory, because the tree holds
# more than this checkout: `worktree/` nests other branches' working copies, and
# a branch that predates the fix still has the rule in its own templates/. A
# directory walk read those as if they were ours and failed the suite from main
# while passing from inside a worktree, which is a property of where the test ran
# and not of what is committed. The index also excludes tests/logs/ and the
# prj--*/ scratch that config tests leave behind mid-run.
function repo_has_bare_mcp_wildcard() {
    local root
    root="$(cd "$(dirname "$0")/../.." && pwd)" || return 1
    git -C "$root" grep -qIE '^[[:space:]]*"mcp__\*",?[[:space:]]*$' -- ':!tests/config/test89*' 2>/dev/null
}
! repo_has_bare_mcp_wildcard
check $? "no bare mcp__* wildcard anywhere in the repo"

# ---------------------------------------------------------------------------
# Trust stamp
# ---------------------------------------------------------------------------
has "$startup" 'hasTrustDialogAccepted' ; check $? "startup stamps the project trusted"
has "$startup" '/proc/self/mountinfo'   ; check $? "startup checks whether the file is a mount"
has "$startup" '.claude.json'           ; check $? "startup targets ~/.claude.json"

finally
