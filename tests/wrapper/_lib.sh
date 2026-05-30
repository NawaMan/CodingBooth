# Shared helpers for tests/wrapper/###-*.sh
# Source this from each test:  source "$(dirname "$0")/_lib.sh"
#
# Each test runs in a fresh container. By default the entrypoint skips dockerd
# (NO_DIND=1) for speed; tests that need an inner Docker set DIND=1 before
# calling run_in_container.

set -euo pipefail

_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "$_LIB_DIR/../.." && pwd)"
IMAGE="${BOOTH_TEST_IMAGE:-booth-wrapper-test}"

# Test name derived from caller's filename, e.g. "001-help".
TEST_NAME="$(basename "${0%.sh}")"

# Colors only when stdout is a TTY.
if [[ -t 1 ]]; then
    _C_GREEN=$'\033[32m'
    _C_RED=$'\033[31m'
    _C_DIM=$'\033[2m'
    _C_OFF=$'\033[0m'
else
    _C_GREEN="" _C_RED="" _C_DIM="" _C_OFF=""
fi

ensure_image() {
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "Image '$IMAGE' missing. Build it first: $_LIB_DIR/build.sh" >&2
        exit 2
    fi
}

# Run a script (passed on stdin) inside a fresh container, return its stdout.
# Stderr passes through to the test's stderr for visibility.
run_in_container() {
    local privileged=() nodind=1
    if [[ "${DIND:-0}" = "1" ]]; then
        privileged=(--privileged)
        nodind=0
    fi
    docker run --rm -i "${privileged[@]}" \
        -e "NO_DIND=$nodind" \
        -v "$REPO_ROOT":/booth:ro \
        -w /work \
        "$IMAGE" \
        bash
}

# Assertions: each prints a hint on failure and exits via fail().
assert_contains() {
    local haystack="$1" needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        fail "expected to contain: $needle"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        fail "expected NOT to contain: $needle"
    fi
}

assert_eq() {
    local actual="$1" expected="$2"
    if [[ "$actual" != "$expected" ]]; then
        fail "expected '$expected', got '$actual'"
    fi
}

pass() {
    printf "%s[PASS]%s %s\n" "$_C_GREEN" "$_C_OFF" "$TEST_NAME"
    exit 0
}

fail() {
    printf "%s[FAIL]%s %s — %s\n" "$_C_RED" "$_C_OFF" "$TEST_NAME" "${1:-failure}" >&2
    if [[ -n "${LAST_OUTPUT:-}" ]]; then
        printf "%s---- captured output ----%s\n%s\n%s-------------------------%s\n" \
            "$_C_DIM" "$_C_OFF" "$LAST_OUTPUT" "$_C_DIM" "$_C_OFF" >&2
    fi
    exit 1
}

ensure_image
