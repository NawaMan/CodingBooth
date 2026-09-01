#!/usr/bin/env bash
# Run every tests/wrapper/###-*.sh in order. Builds the image if missing.
# Usage:
#   tests/wrapper/run-all.sh                  # run all local tests
#   tests/wrapper/run-all.sh --skip-dind      # skip tests declaring DIND=1
#   tests/wrapper/run-all.sh --include-public # also run tests declaring PUBLIC=1
#   tests/wrapper/run-all.sh 001 002          # run only the listed numbers
#
# PUBLIC=1 tests exercise what is CURRENTLY PUBLISHED on codingbooth.io, not the
# wrapper in this checkout, so they can go red for reasons no commit here caused.
# They are opt-in via --include-public (which is what their own headers have
# always documented). Naming one explicitly by number runs it regardless. Once
# included, each self-skips at top-of-script when codingbooth.io / GitHub
# Releases are unreachable, so a transient infra blip becomes [SKIP], not [FAIL].
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${BOOTH_TEST_IMAGE:-booth-wrapper-test}"

skip_dind=false
include_public=false
filter=()
for arg in "$@"; do
    case "$arg" in
        --skip-dind)      skip_dind=true ;;
        --include-public) include_public=true ;;
        *) filter+=("$arg") ;;
    esac
done

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Building image $IMAGE..."
    "$SCRIPT_DIR/build.sh" >/dev/null
fi

shopt -s nullglob
tests=("$SCRIPT_DIR"/[0-9][0-9][0-9]-*.sh)
shopt -u nullglob

if [[ ${#tests[@]} -eq 0 ]]; then
    echo "No tests found in $SCRIPT_DIR" >&2
    exit 2
fi

pass=0
fail=0
skip=0
failed_names=()
retried_names=()   # passed or failed, but only after a second attempt

for test in "${tests[@]}"; do
    name="$(basename "${test%.sh}")"
    number="${name%%-*}"

    # Filter by explicit list.
    named=false
    if [[ ${#filter[@]} -gt 0 ]]; then
        match=false
        for f in "${filter[@]}"; do
            [[ "$number" == "$f" || "$name" == *"$f"* ]] && match=true
        done
        if ! $match; then continue; fi
        named=true
    fi

    # Skip DinD tests if requested — detected by the test declaring DIND=1.
    if $skip_dind && grep -q '^DIND=1' "$test"; then
        printf "[SKIP] %s\n" "$name"
        skip=$((skip + 1))
        continue
    fi

    # PUBLIC tests are opt-in — they measure the deployed site, not this
    # checkout. Asking for one by number counts as opting in.
    if ! $include_public && ! $named && grep -q '^PUBLIC=1' "$test"; then
        printf "[SKIP] %s — public (opt in with --include-public)\n" "$name"
        skip=$((skip + 1))
        continue
    fi

    # Exit-code convention: 0 = PASS, 77 = SKIP (autotools), other = FAIL.
    # PUBLIC tests use exit 77 from public_preflight when codingbooth.io or
    # GitHub Releases are unreachable, so a transient blip becomes SKIP.
    "$test"; rc=$?

    # Retry a real failure once, immediately. 77 is SKIP and 0 is PASS, so
    # neither is retried — only an actual failure. A transient (a registry blip,
    # an unreachable archive) should not cost the whole suite, and the evidence
    # for one is usually inside the container where this runner cannot see it.
    if (( rc != 0 && rc != 77 )); then
        printf "⚠️  FAILED: %s — retrying once\n" "$name"
        retried_names+=("$name")
        "$test"; rc=$?
        if (( rc == 0 )); then
            printf "✅ PASSED after retry: %s\n" "$name"
        fi
    fi

    case "$rc" in
        0)  pass=$((pass + 1)) ;;
        77) skip=$((skip + 1)) ;;
        *)  fail=$((fail + 1)); failed_names+=("$name") ;;
    esac
done

echo ""
echo "==========================="
printf "PASS: %d   FAIL: %d   SKIP: %d\n" "$pass" "$fail" "$skip"
# A pass that needed a second attempt is still a flake — say so rather than
# letting the retry quietly turn an intermittent fault into a green run.
if (( ${#retried_names[@]} > 0 )); then
    printf "⚠️  Retried after a first-attempt failure: %d\n" "${#retried_names[@]}"
    for n in "${retried_names[@]}"; do printf "  - %s\n" "$n"; done
fi
if (( fail > 0 )); then
    printf "Failed:\n"
    for n in "${failed_names[@]}"; do printf "  - %s\n" "$n"; done
    exit 1
fi
