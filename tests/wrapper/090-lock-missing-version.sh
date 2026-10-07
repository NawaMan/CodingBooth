#!/usr/bin/env bash
# 090 — a lock file with no `version=` line must produce the wrapper's own
#       "Invalid lock file" message. Under set -e + pipefail the failed
#       `grep | cut` assignment used to kill the script first: exit 1, no output.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
cp /booth/booth ./booth
mkdir -p .booth/tools
echo "cache=shared" > .booth/tools/codingbooth.lock

echo "=== RUN ==="
./booth list 2>&1
echo "exit=$?"
BASH
)

section="${LAST_OUTPUT##*=== RUN ===}"

assert_contains "$section" "Invalid lock file: missing version"
assert_contains "$section" "exit=1"
pass
