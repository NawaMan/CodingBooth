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
has "$settings" '"Bash(git push --force*)"' ; check $? "keeps force-push denied"

# ---------------------------------------------------------------------------
# ... without the rule Claude Code rejects
# ---------------------------------------------------------------------------
! has "$settings" '"mcp__*"' ; check $? "no bare mcp__* wildcard in the seeded allow list"

# Repo-wide: the rule had been hand-copied into two other settings files — a blog
# booth and the elixir example — so assert on every checked-in copy, not only the
# one this test generates. Anchored to a whole line so that prose mentioning the
# rule (this file, the template's own comment, the CHANGELOG) is not a match.
! grep -rqE '^[[:space:]]*"mcp__\*",?[[:space:]]*$' "$(dirname "$0")/../.." 2>/dev/null
check $? "no bare mcp__* wildcard anywhere in the repo"

# ---------------------------------------------------------------------------
# Trust stamp
# ---------------------------------------------------------------------------
has "$startup" 'hasTrustDialogAccepted' ; check $? "startup stamps the project trusted"
has "$startup" '/proc/self/mountinfo'   ; check $? "startup checks whether the file is a mount"
has "$startup" '.claude.json'           ; check $? "startup targets ~/.claude.json"

finally
