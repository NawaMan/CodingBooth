#!/usr/bin/env bash
# 015 — when the lock file exists but the binary is missing from the shared
#       cache, the wrapper auto-redownloads before dispatching.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
# Nuke the shared cache; the lock file in .booth/tools/ still points at a
# version that's now uncached.
rm -rf ~/.cache/codingbooth
echo "=== DISPATCH ==="
# The binary will likely fail (no docker daemon), but we only need the
# wrapper's redownload behavior — ignore the exit code.
./booth list 2>&1 || true
BASH
)

dispatch_section="${LAST_OUTPUT##*=== DISPATCH ===}"
assert_contains "$dispatch_section" "Binary missing, downloading"
assert_contains "$dispatch_section" "CodingBooth installed:"
pass
