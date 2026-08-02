#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Puppeteer installation
#
# Verifies setup puppeteer installs the package, populates a shared browser
# cache, and can launch headless Chromium inside the booth.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

require_amd64_for_chrome || exit 0

echo "=== Test: Boothfile Puppeteer Installation ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# Test 1: booth starts
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- echo puppeteer-ok) || ACTUAL=""
if [[ "$ACTUAL" == "puppeteer-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts with puppeteer setup"
else
    print_test_result "false" "$0" "1" "booth should start with puppeteer setup"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: shared cache has a Chrome binary
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "find /opt/puppeteer -type f \\( -name chrome -o -name chrome-headless-shell \\) 2>/dev/null | head -1"') || ACTUAL=""
if echo "$ACTUAL" | grep -qE '/opt/puppeteer/'; then
    print_test_result "true" "$0" "2" "PUPPETEER_CACHE_DIR contains a chrome binary"
else
    print_test_result "false" "$0" "2" "PUPPETEER_CACHE_DIR should contain a chrome binary"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: headless launch + blank page
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'bash -lc "
  export PUPPETEER_CACHE_DIR=/opt/puppeteer
  export NODE_PATH=/usr/local/lib/node_modules\${NODE_PATH:+:\$NODE_PATH}
  node -e \"
    const puppeteer = require(\\\"puppeteer\\\");
    (async () => {
      const browser = await puppeteer.launch({
        headless: true,
        args: [\\\"--no-sandbox\\\", \\\"--disable-setuid-sandbox\\\", \\\"--disable-dev-shm-usage\\\"]
      });
      const page = await browser.newPage();
      await page.setContent(\\\"<html><body>ok</body></html>\\\");
      const text = await page.evaluate(() => document.body.textContent);
      await browser.close();
      if (text !== \\\"ok\\\") process.exit(2);
      console.log(\\\"launch-ok\\\");
    })().catch(e => { console.error(e); process.exit(1); });
  \"
"') || ACTUAL=""
if [[ "$ACTUAL" == "launch-ok" ]]; then
    print_test_result "true" "$0" "3" "puppeteer launches headless Chromium"
else
    print_test_result "false" "$0" "3" "puppeteer should launch headless Chromium"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
