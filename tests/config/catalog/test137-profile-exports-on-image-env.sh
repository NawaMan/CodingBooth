#!/bin/bash
# Guard: what a setup's shell profile exports, its template puts on the image env.
#
# `booth exec` runs the command with no shell, so /etc/profile.d never runs.
# A variable or PATH entry that a setup writes only into its profile works in
# an interactive terminal and is missing from `booth exec -- <cmd>`: julia is
# "not found", JAVA_HOME is empty, `go install`ed tools vanish. The fix is an
# `env NAME=...` line in the template's Boothfile segment (see rust, homebrew).
#
# For every setup that writes a profile, each name it exports (PATH counts,
# exported or just assigned) must appear as `env NAME=` in every template or
# extension that emits `setup <name>`, or be listed with a reason in
# profile-only-exports.txt beside this test. That list is for things that are
# right to keep shell-only: prompt cosmetics, values computed per shell, a
# desktop's own session, a service's own start script.
source "$(dirname "$0")/../test-helpers--source.sh"

# Locate repo root (the directory that holds templates/ and variants/).
root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done
allow="$root/tests/config/catalog/profile-only-exports.txt"

# assert-true <condition-result> <message>: pass when the first arg is "0".
function assert-true() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="$1" message="$2"
    local width=64 label="${message} "
    local pad_len=$((width - ${#label})); (( pad_len < 3 )) && pad_len=3
    local pad; pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label}${pad} "
    if [[ "$ok" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1)); echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${message}")  # see test-helpers--source.sh assert-line's comment on the prefix
        echo -e "\033[31mFAILED\033[0m"
    fi
}

# profile-exports <setup-script>: the variable names its profile heredocs set.
# A profile heredoc is one redirected into $PROFILE_FILE (or $PROFILE_CC_FILE,
# ...). Names built from a ${VAR} (JAVA_${JDK_VERSION}_HOME) are skipped: they
# differ per build, so no fixed env line could match them.
function profile-exports() {
    awk '
        !inb && /> *"?\$\{?PROFILE[A-Z_]*FILE\}?"?/ && match($0, /<< *-?[\047"]?[A-Za-z_]+/) {
            term = substr($0, RSTART, RLENGTH); gsub(/[<\047" -]/, "", term); inb = 1; next
        }
        inb && $0 == term { inb = 0; next }
        inb {
            line = $0; sub(/#.*/, "", line)
            if (match(line, /export +[^;]*/)) {                            # export A=.. / export A B
                n = split(substr(line, RSTART + 7, RLENGTH - 7), w, / +/)
                for (i = 1; i <= n; i++) {
                    v = w[i]; sub(/=.*/, "", v)
                    if (v ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print v
                    if (w[i] ~ /=/) break                                  # the value may hold spaces
                }
            }
            if (line ~ /(^|[;)][[:space:]]*|^[[:space:]]+)PATH=/) print "PATH"  # PATH="..:$PATH" in a case arm
        }
    ' "$1" | sort -u
}

# templates-for <setup>: every template/extension whose segments emit `setup <name>`.
function templates-for() {
    find "$root/templates" -name '*.toml' -exec awk -v want="$1" '
        FNR == 1 { seg = 0; inq = 0 }
        !inq && /^\[/ { seg = ($0 ~ /^\[segments\]/) }
        seg && $1 == "setup" && $2 == want { print FILENAME; nextfile }
        { n = gsub(/"""/, "&"); if (n % 2) inq = !inq }
    ' {} +
}

# allowed <setup> <name>: listed in profile-only-exports.txt, by name or as "*".
function allowed() {
    grep -qE "^$1[[:space:]]+(\\*|$2)[[:space:]]+#" "$allow"
}

begin

# --- 1. Every allowlist entry says why ---------------------------------------
bad="$(grep -vE '^[[:space:]]*(#|$)' "$allow" | grep -vE '^[A-Za-z0-9_.-]+[[:space:]]+(\*|[A-Za-z_][A-Za-z0-9_]*)[[:space:]]+#[[:space:]]*[^[:space:]]' || true)"
[[ -z "$bad" ]]; assert-true "$?" "every profile-only-exports.txt entry has a reason"
[[ -n "$bad" ]] && echo "$bad" | sed 's/^/    malformed: /'

# --- 2. Profile exports reach the image env ----------------------------------
checked=0
for script in "$root"/variants/base/setups/*--setup.sh; do
    name="$(basename "$script" --setup.sh)"
    exports="$(profile-exports "$script")"
    [[ -n "$exports" ]] || continue
    tomls="$(templates-for "$name")"
    [[ -n "$tomls" ]] || continue                  # no template: only a hand-written Boothfile uses it
    checked=$((checked + 1))

    for toml in $tomls; do
        rel="${toml#"$root"/templates/}"
        for var in $exports; do
            allowed "$name" "$var" && continue
            grep -qE "^env +${var}=" "$toml"
            assert-true "$?" "${rel%.toml} sets ${var} (${name} profile)"
        done
    done
done

# A changed heredoc shape would empty the loop and pass with nothing checked.
(( checked >= 30 )); assert-true "$?" "setups with a profile examined (${checked} >= 30)"

# --- 3. No stale allowlist entries -------------------------------------------
# An entry for a name the profile no longer exports hides nothing, but it
# reads as a decision someone still stands behind.
while read -r setup var _; do
    [[ -z "$setup" || "$setup" == \#* ]] && continue
    script="$root/variants/base/setups/${setup}--setup.sh"
    if [[ "$var" == "*" ]]; then
        [[ -f "$script" ]]
    else
        [[ -f "$script" ]] && profile-exports "$script" | grep -qx "$var"
    fi
    assert-true "$?" "allowlisted ${setup} ${var} is still exported"
done < "$allow"

finally
