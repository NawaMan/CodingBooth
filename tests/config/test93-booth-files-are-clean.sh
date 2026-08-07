#!/bin/bash
# Guard: the .booth/ files this repo *ships* must stay clean in two ways that
# nothing else checks, and that we have already had to fix by hand once.
#
# 1) No host path. `booth config` echoes its target path verbatim into the
#    "# Configured by:" header, so running it as `booth config /home/you/proj`
#    bakes that path into a committed file — and the release workflow zips it
#    up for every `booth example try`. Nine examples shipped one. Running the
#    command from *inside* the project folder is the fix; this is the guard.
#    /home/coder/ is the *container's* home and is correct everywhere, so only
#    a non-coder home counts.
#
# 2) A .generated must not reference a file that is not there. The manifest is
#    how `booth config` decides whether a Boothfile is still its own output; an
#    entry naming a deleted file is a manifest that has lost track of the tree.
#
# What this deliberately does NOT assert: that every fingerprint still matches.
# A *mismatching* hash is the guard working as designed — it is how the tool
# knows a generated file was hand-edited afterwards, and it is what makes it
# refuse to clobber those edits. playwright-polyglot-example is exactly that
# case, on purpose. (Removing its .generated to "fix" the mismatch does the
# opposite of what it looks like: with a header and no fingerprint the file is
# *adopted* as booth config's own and silently overwritten on the next run.)
#
# Only *committed* files are checked (via git ls-files): they are what ships,
# and it keeps local build junk and .booth/cache out of the sweep. The tradeoff
# is that a file added but not yet committed is invisible here until it lands —
# so this catches what a release would carry, not what a dirty tree holds.
source "$(dirname "$0")/test-helpers--source.sh"

# Locate repo root (the directory that holds templates/ and variants/).
root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done
cd "$root" || exit 1

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

# sha256 of a file, on GNU coreutils or macOS.
function sha256-of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

begin

# --------------------------------------------------------------------------
# 1) No host path in any committed .booth/ file.
# --------------------------------------------------------------------------
# Matches an absolute home path on any platform, minus /home/coder/ — that one
# is the container's own home and appears legitimately in mounts, setup scripts
# and startup hooks throughout .booth/.
leaks="$(git ls-files -- '*/.booth/*' '.booth/*' 2>/dev/null \
         | grep -vE '/\.booth/cache/' \
         | while read -r f; do
             [[ -f "$f" ]] || continue
             if grep -oE '(/home/[A-Za-z0-9_.-]+/|/Users/[A-Za-z0-9_.-]+/)' "$f" 2>/dev/null \
                | grep -qv '^/home/coder/'; then
                 echo "$f"
             fi
           done)"

[[ -z "$leaks" ]]
assert-true "$?" "no committed .booth file carries a host path"
if [[ -n "$leaks" ]]; then
    echo "        offending files:"
    echo "$leaks" | sed 's/^/          /'
    echo "        fix: re-run booth config from INSIDE the project folder, so the"
    echo "             path is not echoed into the '# Configured by:' header."
fi

# --------------------------------------------------------------------------
# 2) No .generated entry names a file that is not there.
# --------------------------------------------------------------------------
missing=""
for manifest in $(git ls-files -- '*/.booth/.generated' '.booth/.generated' 2>/dev/null); do
    dir="$(dirname "$manifest")"
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        name="${line%%=*}"
        [[ -f "$dir/$name" ]] || missing="${missing}${dir}/${name}\n"
    done < "$manifest"
done

[[ -z "$missing" ]]
assert-true "$?" "no .generated entry names a missing file"
if [[ -n "$missing" ]]; then
    echo "        recorded but absent:"
    printf "$missing" | sed 's/^/          /'
    echo "        fix: re-run booth config so the manifest matches the tree, or drop"
    echo "             the stale entry if the file was removed on purpose."
fi

finally
