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

DOCKER_ARCH="$(docker_server_arch)"

echo "=== Test: Boothfile Puppeteer Installation ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# On arm64 the setup reaches for cb-install-chromium.sh, which lives in the base
# image — so this has to build against a locally rebuilt base rather than the
# published one. Skip cleanly when there isn't one.
use_local_base_image || exit $FAILED

# Test 1: booth starts
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- echo puppeteer-ok) || ACTUAL=""
if [[ "$ACTUAL" == "puppeteer-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts with puppeteer setup"
else
    print_test_result "false" "$0" "1" "booth should start with puppeteer setup"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: a browser Puppeteer can drive is baked into the image.
# amd64 downloads Chrome for Testing into the shared cache; arm64 has no such
# build to download, so the setup installs system Chromium and points
# PUPPETEER_EXECUTABLE_PATH at it. Either way the browser must be there at
# build time — a runtime download would defeat the shared, world-readable cache.
if [[ "$DOCKER_ARCH" == "arm64" ]]; then
    ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "test -x \"\$PUPPETEER_EXECUTABLE_PATH\" && echo \"\$PUPPETEER_EXECUTABLE_PATH\""') || ACTUAL=""
    EXPECT_DESC="PUPPETEER_EXECUTABLE_PATH points at an executable Chromium"
    MATCH='chromium'
else
    ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "find /opt/puppeteer -type f \\( -name chrome -o -name chrome-headless-shell \\) 2>/dev/null | head -1"') || ACTUAL=""
    EXPECT_DESC="PUPPETEER_CACHE_DIR contains a chrome binary"
    MATCH='/opt/puppeteer/'
fi
if echo "$ACTUAL" | grep -qE "$MATCH"; then
    print_test_result "true" "$0" "2" "$EXPECT_DESC"
else
    print_test_result "false" "$0" "2" "$EXPECT_DESC"
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
