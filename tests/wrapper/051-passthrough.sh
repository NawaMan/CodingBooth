#!/usr/bin/env bash
# 051 — non-wrapper commands (e.g. `list`) get dispatched to the binary.
#       The binary may error (no docker daemon), but the wrapper-level help
#       text must not appear — that would mean the wrapper ate the command.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
echo "=== LIST ==="
./booth list 2>&1 || true
echo "=== HELP-FOR-CONTROL ==="
./booth help
BASH
)

list_section="${LAST_OUTPUT#*=== LIST ===}"; list_section="${list_section%%=== HELP-FOR-CONTROL*}"
help_section="${LAST_OUTPUT##*=== HELP-FOR-CONTROL ===}"

# Wrapper help text must NOT show up for `list`. If it did, the wrapper
# intercepted instead of dispatching.
assert_not_contains "$list_section" "Wrapper commands:"
assert_not_contains "$list_section" "install --cache=shared"

# Control: `help` IS handled by the wrapper.
assert_contains "$help_section" "Wrapper commands:"
pass
