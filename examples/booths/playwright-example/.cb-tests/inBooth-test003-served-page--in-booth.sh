#!/bin/bash
# Test: headless Chromium drives a page served over HTTP (start the app, then test it)
set -euo pipefail
echo "=== Testing playwright against a served page ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
[ -d node_modules/@playwright/test ] || npm ci
npx playwright test -c playwright.served.config.ts --reporter=list
