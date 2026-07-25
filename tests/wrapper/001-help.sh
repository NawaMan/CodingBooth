#!/usr/bin/env bash
# 001 — ./booth help prints the wrapper help (no install, no network).
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth help
BASH
)

assert_contains "$LAST_OUTPUT" "Wrapper commands:"
assert_contains "$LAST_OUTPUT" "install [VERSION]"
assert_contains "$LAST_OUTPUT" "uninstall"
assert_contains "$LAST_OUTPUT" "shell-config"
assert_contains "$LAST_OUTPUT" "create <dir>"
# tools-cache moved to the binary; update-wrapper is gone.
assert_not_contains "$LAST_OUTPUT" "tools-cache"
assert_not_contains "$LAST_OUTPUT" "update-wrapper"
pass
