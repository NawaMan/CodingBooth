#!/usr/bin/env bash
# Run every tests/wrapper/###-*.sh in order. Builds the image if missing.
# Usage:
#   tests/wrapper/run-all.sh                 # run all tests (local-source tests)
#   tests/wrapper/run-all.sh --skip-dind     # skip tests declaring DIND=1
#   tests/wrapper/run-all.sh --include-public  # also run PUBLIC=1 tests
#                                            # (hit codingbooth.io, test what's
#                                            #  published — not your local diff)
#   tests/wrapper/run-all.sh 001 002         # run only the listed numbers
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

for test in "${tests[@]}"; do
    name="$(basename "${test%.sh}")"
    number="${name%%-*}"

    # Filter by explicit list.
    if [[ ${#filter[@]} -gt 0 ]]; then
        match=false
        for f in "${filter[@]}"; do
            [[ "$number" == "$f" || "$name" == *"$f"* ]] && match=true
        done
        if ! $match; then continue; fi
    fi

    # Skip DinD tests if requested — detected by the test declaring DIND=1.
    if $skip_dind && grep -q '^DIND=1' "$test"; then
        printf "[SKIP] %s\n" "$name"
        skip=$((skip + 1))
        continue
    fi

    # PUBLIC=1 tests exercise codingbooth.io / the published wrapper, not your
    # local changes. Skip by default; only run when --include-public is given.
    if grep -q '^PUBLIC=1' "$test" && ! $include_public; then
        printf "[SKIP] %s (public — pass --include-public)\n" "$name"
        skip=$((skip + 1))
        continue
    fi

    if "$test"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failed_names+=("$name")
    fi
done

echo ""
echo "==========================="
printf "PASS: %d   FAIL: %d   SKIP: %d\n" "$pass" "$fail" "$skip"
if (( fail > 0 )); then
    printf "Failed:\n"
    for n in "${failed_names[@]}"; do printf "  - %s\n" "$n"; done
    exit 1
fi
