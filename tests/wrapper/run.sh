#!/usr/bin/env bash
# Run the booth-wrapper test container.
#   /booth  is the CodingBooth source, mounted read-only from the repo
#   /work   is an empty scratch dir owned by 'tester' — start booth tests here
#
# Usage:
#   tests/wrapper/run.sh                  # interactive bash, dockerd auto-started
#   tests/wrapper/run.sh bash -c '...'    # run a one-off command, then exit
#   NO_DIND=1 tests/wrapper/run.sh ...    # skip starting dockerd inside
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
IMAGE="${BOOTH_TEST_IMAGE:-booth-wrapper-test}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image '$IMAGE' not found. Building..."
    "$SCRIPT_DIR/build.sh"
fi

tty_flags=()
if [[ -t 0 && -t 1 ]]; then
    tty_flags=(-it)
fi

exec docker run --rm "${tty_flags[@]}" \
    --privileged \
    -e "NO_DIND=${NO_DIND:-0}" \
    -v "$REPO_ROOT":/booth:ro \
    -w /work \
    "$IMAGE" \
    "$@"
