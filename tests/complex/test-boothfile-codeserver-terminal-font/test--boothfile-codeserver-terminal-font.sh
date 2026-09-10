#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: code-server integrated terminal Nerd Font (Fira Code)
#
# Builds a real booth with `setup codeserver` and checks that the integrated
# terminal's font actually works: the Fira Code Nerd Font is installed
# (codeserver carries no desktop toolkit, so fontconfig itself has to be
# pulled in too — the bug this test guards against) and resolvable by
# fontconfig, and start-codeserver's settings.json carries
# terminal.integrated.fontFamily, with code-server actually starting.
#
# codeserver--setup.sh and fira-code-nerd-font--setup.sh are loaded from
# .booth/setups/ (mirror variants/base/setups/) until the released base image
# ships the font install.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: code-server integrated terminal Nerd Font (Fira Code) ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

booth_first() {
    capture_codingbooth "head -1" --silence-build -- "$@"
}

# Test 1: booth starts and can run a trivial command
ACTUAL=$(booth_first echo codeserver-font-ok) || ACTUAL=""
if [[ "$ACTUAL" == "codeserver-font-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts and runs a command"
else
    print_test_result "false" "$0" "1" "booth should start and run a command"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

# Test 2: fontconfig actually resolves the Nerd Font (not just a file on disk).
# Not the container's very first exec'd command: a leading statement avoids a
# cold-container fontconfig race (see the XFCE terminal font test for detail).
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'echo ready; fc-match "FiraCode Nerd Font Mono"') || ACTUAL=""
if echo "$ACTUAL" | grep -qi "FiraCodeNerdFontMono"; then
    print_test_result "true" "$0" "2" "fontconfig resolves FiraCode Nerd Font Mono"
else
    print_test_result "false" "$0" "2" "fontconfig should resolve FiraCode Nerd Font Mono"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: start-codeserver writes settings.json with the Nerd Font, and
# code-server actually starts and serves its HTTP port.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  nohup start-codeserver >/tmp/scs.log 2>&1 &
  for _ in $(seq 1 20); do
    grep -q "HTTP server listening" /tmp/scs.log 2>/dev/null && break
    sleep 1
  done
  cat "$HOME/.local/share/code-server/User/settings.json" 2>&1
  echo "---log---"
  grep -o "HTTP server listening" /tmp/scs.log || true
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '"terminal.integrated.fontFamily": "FiraCode Nerd Font Mono"' \
   && echo "$ACTUAL" | grep -q "HTTP server listening"; then
    print_test_result "true" "$0" "3" "code-server starts and settings.json carries the Nerd Font"
else
    print_test_result "false" "$0" "3" "code-server should start and settings.json should carry the Nerd Font"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
