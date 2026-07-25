#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Cypress installation
#
# Verifies setup cypress installs the CLI and binary cache, and that
# `cypress verify` succeeds inside the booth.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Cypress Installation ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# Test 1: booth starts
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- echo cypress-ok) || ACTUAL=""
if [[ "$ACTUAL" == "cypress-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts with cypress setup"
else
    print_test_result "false" "$0" "1" "booth should start with cypress setup"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: cypress CLI reports a version
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'bash -lc "export CYPRESS_CACHE_FOLDER=/opt/cypress; cypress --version 2>/dev/null || npx cypress --version"') || ACTUAL=""
if echo "$ACTUAL" | grep -qiE 'Cypress package version|cypress'; then
    print_test_result "true" "$0" "2" "cypress CLI reports a version"
else
    print_test_result "false" "$0" "2" "cypress CLI should report a version"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: binary cache populated + verify
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'bash -lc "
  export CYPRESS_CACHE_FOLDER=/opt/cypress
  if [[ ! -d /opt/cypress ]] || [[ -z \"\$(ls -A /opt/cypress 2>/dev/null)\" ]]; then
    echo cache-empty
    exit 0
  fi
  if cypress verify >/tmp/cv.out 2>&1 || npx cypress verify >/tmp/cv.out 2>&1; then
    echo verify-ok
  else
    cat /tmp/cv.out
    echo verify-fail
  fi
"') || ACTUAL=""
if [[ "$ACTUAL" == "verify-ok" ]]; then
    print_test_result "true" "$0" "3" "cypress verify succeeds against shared cache"
else
    print_test_result "false" "$0" "3" "cypress verify should succeed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
