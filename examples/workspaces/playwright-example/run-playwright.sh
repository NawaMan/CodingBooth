#!/bin/bash
# Run Playwright tests
set -e
cd "$(dirname "$0")"
# Install project deps (node_modules is git-ignored). Browsers are pre-baked
# into the booth image, so this does not download any browser at runtime.
npm ci
npx playwright test
