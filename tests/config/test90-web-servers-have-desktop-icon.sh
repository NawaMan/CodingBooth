#!/bin/bash
# Guard: every setup that installs a web-UI server must register a desktop icon
# with cb-web-icon.sh. The launcher is what makes the service reachable on the
# desktop variants — without it the tool installs and serves, but nothing on the
# desktop points at it, and only someone who knows the starter name can find it.
# Excalidraw, Mermaid and PlantUML all shipped that way until this guard existed.
#
# A web-UI server is derived, not listed: a setup that installs a
# /usr/local/bin/start-<name> launcher AND documents an http://localhost: URL.
# Desktop environments match that shape too (they serve their own session over
# HTTP), but they *host* the icons rather than needing one, so they are excluded.
source "$(dirname "$0")/test-helpers--source.sh"

# Locate repo root (the directory that holds templates/ and variants/).
root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done

# The desktop environments themselves — they draw the desktop the icons land on.
EXCLUDED=(xfce kde lxqt wayland)

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
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("Test ${TEST_COUNT}: ${message}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

# Fold backslash-continued lines so a multi-line cb-web-icon.sh call reads as one.
function joined() { sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$1"; }

begin

ids=""
found=0
for script in "$root"/variants/base/setups/*--setup.sh; do
    name="$(basename "$script" --setup.sh)"

    # Does this setup install a web-UI server?
    starter="$(grep -om1 '/usr/local/bin/start-[a-z0-9-]*' "$script" || true)"
    [[ -n "$starter" ]]                          || continue
    grep -q 'http://localhost:' "$script"        || continue

    skip=false
    for excluded in "${EXCLUDED[@]}"; do
        [[ "$name" == "$excluded" ]] && skip=true
    done
    [[ "$skip" == "true" ]] && continue

    found=$((found + 1))
    # Anchored to the start of a line so a mention of cb-web-icon.sh in a comment
    # is not mistaken for the call — viewmd-desktop-icon--setup.sh explains itself
    # in its header and tripped exactly that.
    call="$(joined "$script" | grep -m1 -E '^[[:space:]]*cb-web-icon\.sh' || true)"

    [[ -n "$call" ]]; assert-true "$?" "${name} registers a desktop icon"
    [[ -n "$call" ]] || continue

    # The icon must launch the starter this same setup installs, or clicking it
    # opens a service nothing ever starts.
    want="$(basename "$starter")"
    # [ =][ =]* rather than [ =]\+ — BSD sed (macOS) reads \+ as a literal plus.
    got="$(sed -n 's/.*--start[ =][ =]*\([^ ]*\).*/\1/p' <<<"$call")"
    [[ "$got" == "$want" ]]
    assert-true "$?" "${name} icon starts ${want}"

    id="$(sed -n 's/.*--id[ =][ =]*\([^ ]*\).*/\1/p' <<<"$call")"
    ids+="${id}"$'\n'
done

# The derivation must keep finding services; a rename that silently empties the
# candidate list would turn this whole guard into a no-op that always passes.
(( found >= 7 )); assert-true "$?" "web-UI server setups found (${found} >= 7)"

# Ids key /etc/cb-web-services/<id>.conf — a duplicate would overwrite a descriptor.
[[ -z "$(sort <<<"$ids" | uniq -d | tr -d '[:space:]')" ]]
assert-true "$?" "web-service ids are unique"

finally
