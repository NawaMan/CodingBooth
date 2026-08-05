#!/bin/bash
# Guard: a tool with no build for some architecture must degrade, not explode.
#
# Google publishes no linux/arm64 build of Chrome, so on Apple Silicon there is
# nothing for google-chrome--setup.sh to install. Two rules follow, and this
# test holds both:
#
#  1. The setup warns and exits 0. A browser that upstream never built must not
#     take down a build in which every other setup succeeded — the booth is
#     still useful, minus one tool.
#  2. The template says so in template.toml, via unsupported-arch. That is what
#     the config TUI reads to mark the row, explain it in the detail panel, and
#     warn on select, so nobody ticks the box and finds out later.
#
# Rule 2 is the one that rots quietly: a setup can gain an arch bail-out without
# anyone remembering the metadata, and the TUI would go back to saying nothing.
source "$(dirname "$0")/test-helpers--source.sh"

# Locate repo root (the directory that holds templates/ and variants/).
root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done

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

begin

# --- 1. Setups that give up on an architecture must warn, not fail -----------
#
# The shape we look for: a top-level `if` that tests the machine's architecture
# for arm64/aarch64 and then stops the script early. Branches that stop early
# are the bail-outs; branches that fall through are workarounds that go on to
# install something (elm fetches a community aarch64 build that way), and those
# are none of this test's business.
#
# sed -E throughout: BSD sed (macOS) has no \| alternation in a basic regex, so
# a BRE here would match nothing and pass vacuously.
checked=0
for script in "$root"/variants/base/setups/*--setup.sh; do
    name="$(basename "$script" --setup.sh)"

    grep -qE '^[[:space:]]*if .*(dpkg --print-architecture|\$arch|\$ARCH).*(arm64|aarch64)' "$script" || continue
    branch="$(sed -n -E '/^[[:space:]]*if .*(arm64|aarch64)/,/^fi$/p' "$script")"

    # No early exit => the branch installs something. Not a bail-out.
    grep -qE '^[[:space:]]*exit [0-9]+[[:space:]]*$' <<<"$branch" || continue
    checked=$((checked + 1))

    grep -qE '^[[:space:]]*exit 0[[:space:]]*$' <<<"$branch"
    assert-true "$?" "${name} exits 0 when it cannot install"

    # The whole point: a missing upstream build must not fail the build.
    ! grep -qE '^[[:space:]]*exit 1[[:space:]]*$' <<<"$branch"
    assert-true "$?" "${name} does not hard-fail on an unsupported arch"

    # And it must actually say something — a silent skip is how this started.
    grep -qiE 'not available|not supported|no .*build|⚠' <<<"$branch"
    assert-true "$?" "${name} explains why it skipped"
done

# If the shape above stops matching, every assertion in the loop disappears and
# the suite goes quiet without anything having been verified.
(( checked >= 1 )); assert-true "$?" "arch bail-out setups examined (${checked} >= 1)"

# --- 2. Every unsupported-arch declaration carries a note --------------------
#
# The TUI falls back to a generic sentence without one, which tells the user
# that something is missing but not what to do instead.
declared=0
while IFS= read -r toml; do
    grep -q '^unsupported-arch[[:space:]]*=' "$toml" || continue
    declared=$((declared + 1))
    tname="$(basename "$(dirname "$toml")")"

    grep -q '^unsupported-arch-note[[:space:]]*=' "$toml"
    assert-true "$?" "${tname} pairs unsupported-arch with a note"
done < <(find "$root/templates" -name template.toml)

# --- 3. google-chrome is declared, and chromium is not ----------------------
#
# The concrete case this guard was built for. chromium is the counter-example:
# Debian builds it for arm64, so flagging it would send people to a workaround
# they do not need.
chrome_toml="$root/templates/browsers/google-chrome/template.toml"
grep -qE '^unsupported-arch[[:space:]]*=.*arm64' "$chrome_toml"
assert-true "$?" "google-chrome declares arm64 unsupported"

grep -qiE 'chromium' "$chrome_toml"
assert-true "$?" "google-chrome's note points at an alternative"

chromium_toml="$root/templates/browsers/chromium/template.toml"
! grep -q '^unsupported-arch[[:space:]]*=' "$chromium_toml"
assert-true "$?" "chromium is not flagged (Debian builds it for arm64)"

# The scan must keep finding declarations; a renamed key would silently empty
# the loop above and turn section 2 into a no-op that always passes.
(( declared >= 1 )); assert-true "$?" "unsupported-arch declarations found (${declared} >= 1)"

finally
