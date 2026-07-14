#!/bin/bash
# `booth config` must not emit a config that docker will refuse to start.
#
# Docker cannot bind one host port twice, and run-args grow duplicates easily: a template's
# short-form "-p" plus the user's long-form "--publish" for the same mapping, or two
# templates whose params resolve to the same mapping (the compiler's own dedup runs before
# params are expanded, so "${NGINX_PORT}:80" and "${APACHE_PORT}:80" look distinct to it).
#
# Identical mappings are redundant, not conflicting: collapse them. Publishing one container
# port on *two* host ports is legal, so it is kept — but it is rarely what was meant, so the
# user is told the first mapping stays bound and pointed at the way to actually move it.
#
# The runtime half — refusing a booth whose ports cannot all bind — is tests/dryrun/test024.
source "$(dirname "$0")/test-helpers--source.sh"

begin
config="$prj/.booth/config.toml"

# has <file> <substring> — 0 when the file contains it
function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }

# count <file> <substring> — how many lines contain it
function count() { grep -cF -- "${2}" "${1}" 2>/dev/null || true ; }

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

# ---------------------------------------------------------------------------
# The same mapping from a template and from --expose: one mapping, not two.
# The user-owned long form is the keeper — reconfiguring reads it back into --expose.
# ---------------------------------------------------------------------------
rm -rf "$prj/.booth"
run booth config $prj --no-tui --overwrite --select "cloudbeaver+expose" --expose 8978:8978
# The quoted form: the "# Configured by:" header echoes the flag text as well.
[[ "$(count "$config" '"8978:8978"')" == "1" ]] ; check $? "a mapping given twice is published once"
has "$config" '"--publish", "8978:8978"'      ; check $? "the user-owned long form is the one kept"

# ---------------------------------------------------------------------------
# Two templates that both default to host 8080 — no --expose involved at all.
# ---------------------------------------------------------------------------
rm -rf "$prj/.booth"
run booth config $prj --no-tui --overwrite --select "nginx+expose/apache+expose"
[[ "$(count "$config" '"8080:80"')" == "1" ]] ; check $? "two templates on one mapping publish it once"

# ---------------------------------------------------------------------------
# Both spellings of a booth-relative mapping collapse the same way.
# ---------------------------------------------------------------------------
rm -rf "$prj/.booth"
run booth config $prj --no-tui --overwrite --select "cloudbeaver+expose:+8978" --expose "+8978:8978"
[[ "$(count "$config" '"+8978:8978"')" == "1" ]] ; check $? "a relative mapping given twice is published once"

# ---------------------------------------------------------------------------
# A --expose on a *different* host port is additive, and docker allows it — so keep both,
# and say so, because the template's mapping stays bound.
# ---------------------------------------------------------------------------
rm -rf "$prj/.booth"
warning="$prj/warning.txt"
booth config $prj --no-tui --overwrite --select "cloudbeaver+expose" --expose 19000:8978 2> "$warning" >/dev/null

has "$config"  '"-p", "8978:8978"'       ; check $? "the template mapping is kept"
has "$config"  '"--publish", "19000:8978"' ; check $? "the --expose mapping is kept alongside it"
has "$warning" 'adds a second mapping'   ; check $? "the user is told it adds rather than moves"
has "$warning" '+expose:19000'           ; check $? "the warning names the way to actually move it"

# ---------------------------------------------------------------------------
# Moving the host port the intended way publishes exactly one mapping, no warning.
# ---------------------------------------------------------------------------
rm -rf "$prj/.booth"
booth config $prj --no-tui --overwrite --select "cloudbeaver+expose:19000" 2> "$warning" >/dev/null

has   "$config"  '"19000:8978"'          ; check $? "+expose:19000 publishes 19000:8978"
! has "$config"  '"8978:8978"'           ; check $? "…and 8978 is no longer bound"
! has "$warning" 'adds a second mapping' ; check $? "…with nothing to warn about"

finally
