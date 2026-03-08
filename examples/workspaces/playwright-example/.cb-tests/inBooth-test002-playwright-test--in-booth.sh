#!/bin/bash
# Test: Playwright tests run successfully
echo "=== Testing playwright test run ==="
cd ~/code
npm install --ignore-scripts
npx playwright install --with-deps chromium
npx playwright test
