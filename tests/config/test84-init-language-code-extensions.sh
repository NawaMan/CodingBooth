#!/bin/bash
# Every languages/*/vscode-ext--extension.toml must name a setup script that exists.
#
# This is data-driven over the whole catalog rather than a list of hand-picked
# languages, because the bug it guards against was invisible per-language:
# fsharp's extension emitted `setup code-extension ionide.ionide-fsharp`, and no
# such setup script exists — the compiler only *warns* on an unknown setup script
# and emits the RUN anyway, so the build died at `code-extension--setup.sh: not
# found`. It was auto-select = true, so every `--select fsharp` was affected, and
# it survived from 48157fb4 because nothing checked the reference resolved.
#
# Two assertions per language, plus the auto-select contract:
#   1. the setup script named in the segment exists in variants/base/setups/
#   2. compiling the selection produces no "Unknown setup script" warning
#
# Add a language extension and it is covered here automatically — no edit needed.
source "$(dirname "$0")/test-helpers--source.sh"

begin

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATES="$REPO_ROOT/templates/languages"
SETUPS="$REPO_ROOT/variants/base/setups"

# Languages whose VS Code extension is deliberately NOT auto-selected. Roc's only
# published extension is third-party and self-described as unofficial, so it ships
# opt-in; every other language's is on by default.
OPT_IN_LANGS=" roc "

pass() {
    TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1))
    printf 'Test %d: %s ' "$TEST_COUNT" "$1"
    printf '%.0s.' $(seq 1 $(( 62 - ${#1} > 0 ? 62 - ${#1} : 3 )))
    echo -e " \033[32mPASSED\033[0m"
}
fail() {
    TEST_COUNT=$((TEST_COUNT + 1)); FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: $1")
    printf 'Test %d: %s ' "$TEST_COUNT" "$1"
    printf '%.0s.' $(seq 1 $(( 62 - ${#1} > 0 ? 62 - ${#1} : 3 )))
    echo -e " \033[31mFAILED\033[0m"
    [[ -n "${2:-}" ]] && echo "  $2"
}

FOUND=0
for toml in "$TEMPLATES"/*/vscode-ext--extension.toml; do
    [[ -f "$toml" ]] || continue
    lang="$(basename "$(dirname "$toml")")"
    FOUND=$((FOUND + 1))

    # --- 1. every setup named in the segment must exist -----------------------
    # A language may legitimately point at a shared setup (csharp -> dotnet), so
    # resolve whatever name is there rather than assuming <lang>-code-extension.
    named="$(grep -oE '^setup +[a-z0-9._-]+' "$toml" | awk '{print $2}' | sort -u)"
    if [[ -z "$named" ]]; then
        fail "$lang: extension declares a setup" "no 'setup <name>' line in $toml"
    else
        missing=""
        for s in $named; do
            [[ -f "$SETUPS/${s}--setup.sh" ]] || missing="${missing} ${s}"
        done
        if [[ -z "$missing" ]]; then
            pass "$lang: setup script exists ($(echo $named | tr '\n' ' '))"
        else
            fail "$lang: setup script exists" "no such script:${missing} (expected $SETUPS/<name>--setup.sh)"
        fi
    fi

    # --- 2. the selection must compile with no unknown-script warning ---------
    run rm -Rf "$prj"; mkdir -p "$prj"
    sel="$lang"
    [[ "$OPT_IN_LANGS" == *" $lang "* ]] && sel="${lang}+vscode-ext"
    run booth config "$prj" --no-tui --variant codeserver --select "$sel"
    warns="$(booth emit-dockerfile --code "$prj" 2>&1 | grep "Unknown setup script" || true)"
    if [[ -z "$warns" ]]; then
        pass "$lang: compiles with no unknown-script warning"
    else
        fail "$lang: compiles with no unknown-script warning" "$warns"
    fi

    # --- 3. auto-select contract ---------------------------------------------
    run rm -Rf "$prj"; mkdir -p "$prj"
    run booth config "$prj" --no-tui --variant codeserver --select "$lang"
    got_ext=no
    for s in $named; do
        grep -qE "^setup +${s}\b" "$prj/.booth/Boothfile" && got_ext=yes
    done
    if [[ "$OPT_IN_LANGS" == *" $lang "* ]]; then
        if [[ "$got_ext" == "no" ]]; then
            pass "$lang: opt-in, absent from a bare --select"
        else
            fail "$lang: opt-in, absent from a bare --select" "extension was auto-selected but should not be"
        fi
    else
        if [[ "$got_ext" == "yes" ]]; then
            pass "$lang: auto-selected by a bare --select"
        else
            fail "$lang: auto-selected by a bare --select" "extension missing from a bare --select ${lang}"
        fi
    fi
done

# Guard the guard: if the glob ever matches nothing this test would pass vacuously.
if [[ "$FOUND" -ge 25 ]]; then
    pass "found $FOUND language extensions to check"
else
    fail "found enough language extensions" "only $FOUND matched — expected >= 25, glob or layout changed?"
fi

finally
