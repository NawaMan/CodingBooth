#!/bin/bash
# Run Playwright tests
cd "$(dirname "$0")"
npx playwright test
