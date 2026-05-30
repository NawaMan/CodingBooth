#!/usr/bin/env bash
# 017 — `tools-cache` must be passed through to the binary, not intercepted
#       by the wrapper. Regression guard for anyone adding a `tools-cache)`
#       case back to the wrapper's COMMAND dispatch.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
echo "=== TOOLS-CACHE LIST ==="
./booth tools-cache list 2>&1 || true
BASH
)

passthrough_section="${LAST_OUTPUT##*=== TOOLS-CACHE LIST ===}"

# If the wrapper intercepted, we'd see wrapper-help text or the old wrapper
# internal error. Either of these in the output is a regression.
assert_not_contains "$passthrough_section" "Wrapper commands:"
assert_not_contains "$passthrough_section" "Unknown tools-cache command:"
pass
