#!/bin/bash
# Test: Playwright tests run successfully
echo "=== Testing playwright test run ==="
cd "$(dirname "$0")/.."
just test
