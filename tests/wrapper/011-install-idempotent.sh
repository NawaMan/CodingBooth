#!/usr/bin/env bash
# 011 — running ./booth install a second time with no version arg detects the
#       existing lock file and exits without re-downloading.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
echo "=== SECOND RUN ==="
./booth install
BASH
)

assert_contains "$LAST_OUTPUT" "=== SECOND RUN ==="
assert_contains "$LAST_OUTPUT" "already installed"
# The "Downloading" message must not appear in the second run's section.
second_run="${LAST_OUTPUT##*=== SECOND RUN ===}"
assert_not_contains "$second_run" "Downloading CodingBooth binary"
pass
