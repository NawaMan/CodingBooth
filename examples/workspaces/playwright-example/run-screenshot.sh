#!/bin/bash
# Visit a web page and capture a screenshot with headless Chromium.
#   ./run-screenshot.sh [url] [outfile]
set -e
cd "$(dirname "$0")"
# Install project deps (node_modules is git-ignored). The browser is pre-baked
# into the booth image, so no browser is downloaded at runtime.
npm ci
URL="${1:-https://news.ycombinator.com/}"
OUT="${2:-screenshot.png}"
node screenshot.js "$URL" "$OUT"
echo "Open $OUT on your host to view the captured page."
