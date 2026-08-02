#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Selenium drivers installation
#
# Verifies setup selenium installs Chrome for Testing + chromedriver under
# /opt/selenium and that both report versions on PATH.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

require_amd64_for_chrome || exit 0

echo "=== Test: Boothfile Selenium Drivers Installation ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# Test 1: booth starts
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- echo selenium-ok) || ACTUAL=""
if [[ "$ACTUAL" == "selenium-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts with selenium setup"
else
    print_test_result "false" "$0" "1" "booth should start with selenium setup"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: chromedriver on PATH
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "chromedriver --version"') || ACTUAL=""
if echo "$ACTUAL" | grep -qiE 'ChromeDriver|[0-9]+\.[0-9]+'; then
    print_test_result "true" "$0" "2" "chromedriver is on PATH"
else
    print_test_result "false" "$0" "2" "chromedriver should be on PATH"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: chrome / Chrome for Testing on PATH
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "chrome --version || google-chrome --version"') || ACTUAL=""
if echo "$ACTUAL" | grep -qiE 'Chrome|Chromium|[0-9]+\.[0-9]+'; then
    print_test_result "true" "$0" "3" "chrome binary is on PATH"
else
    print_test_result "false" "$0" "3" "chrome binary should be on PATH"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: headless chrome can start (no full Selenium language binding needed)
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'bash -lc "
  chrome --headless=new --no-sandbox --disable-gpu --dump-dom about:blank 2>/dev/null | head -1 | grep -qi html && echo headless-ok || echo headless-fail
"') || ACTUAL=""
if [[ "$ACTUAL" == "headless-ok" ]]; then
    print_test_result "true" "$0" "4" "chrome headless dump-dom works"
else
    print_test_result "false" "$0" "4" "chrome headless dump-dom should work"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
