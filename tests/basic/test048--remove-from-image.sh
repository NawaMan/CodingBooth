#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: "~name" takes a tool the base image ships out of the booth
#
# glow and ttt are baked into base. A booth configured with ~glow/~ttt runs
# their remove steps after every install, so neither command is left, and with
# ttt gone $EDITOR and /usr/local/bin/editor fall back to nano. A tool the
# selection did not name (lazygit) stays.
#
# Test 1: glow and ttt are gone, lazygit is still there
# Test 2: EDITOR and the editor link point at nano
#
# Deliberately NOT `set -e`: each check reports what it got instead.
# -------------------------------------------------------

FAILED=0

FIXTURE="$(mktemp -d)"
cleanup() {
  run_coding_booth remove --name "$(basename "$FIXTURE")" >/dev/null 2>&1 || true
  docker rmi "$(docker images --format '{{.Repository}}:{{.Tag}}' codingbooth-local | grep "^codingbooth-local:$(basename "$FIXTURE")-" | head -1)" >/dev/null 2>&1 || true
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

export CB_TEMPLATES_PATH="$(cd ../.. && pwd)/templates"
run_coding_booth config "$FIXTURE" --no-tui --select '~glow/~ttt' >/dev/null 2>&1
cat > "$FIXTURE/check.sh" <<'CHECK'
printf 'glow=%s ttt=%s lazygit=%s\n' \
  "$(command -v glow || echo gone)" "$(command -v ttt || echo gone)" "$(command -v lazygit || echo gone)"
printf 'EDITOR=%s editor=%s\n' "$EDITOR" "$(readlink -f /usr/local/bin/editor)"
CHECK

OUT="$(run_coding_booth --code "$FIXTURE" --silence-build -- bash check.sh 2>&1)" || true

TOOLS="$(printf '%s\n' "$OUT" | grep '^glow=' | tail -1)"
if [[ "$TOOLS" == "glow=gone ttt=gone lazygit=/usr/local/bin/lazygit" ]]; then
  print_test_result "true" "$0" "1" "~glow/~ttt removes both and leaves lazygit"
else
  print_test_result "false" "$0" "1" "expected glow and ttt gone, lazygit kept, got '$TOOLS'"
  printf '%s\n' "${OUT:-<empty — the booth did not run>}" | tail -8 | sed 's/^/  | /'
  FAILED=$((FAILED + 1))
fi

EDITORS="$(printf '%s\n' "$OUT" | grep '^EDITOR=' | tail -1)"
if [[ "$EDITORS" == "EDITOR=nano editor=/usr/bin/nano" ]]; then
  print_test_result "true" "$0" "2" "With ttt removed, EDITOR and editor fall back to nano"
else
  print_test_result "false" "$0" "2" "expected EDITOR=nano editor=/usr/bin/nano, got '$EDITORS'"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
