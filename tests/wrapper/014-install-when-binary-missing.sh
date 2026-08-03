#!/usr/bin/env bash
# 014 — when the lock file exists but the binary is missing from the shared
#       cache, `./booth install` (no version arg) re-installs the pinned
#       binary instead of falsely reporting "already installed".
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
# Nuke the shared cache; the lock file in .booth/tools/ still points at a
# version that's now uncached.
rm -rf ~/.cache/codingbooth
echo "=== REINSTALL ==="
./booth install
BASH
)

reinstall_section="${LAST_OUTPUT##*=== REINSTALL ===}"
# Must NOT short-circuit as already-installed when the binary is gone.
assert_not_contains "$reinstall_section" "already installed"
# Must recognize the missing binary and download it.
assert_contains "$reinstall_section" "binary is missing"
assert_contains "$reinstall_section" "CodingBooth installed:"
pass
