#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: the Console UI's layouts, i3-style Ctrl+Alt tiling and CodingBooth Help, in
# a real browser against a real booth. The layout logic has its own Node test
# (tests/setups/test--console-tiling.sh); this is the page side it cannot see —
# keys pressed inside a ttyd terminal reaching the console, panes moving
# without their terminals reloading, and the Help dialog's added tab actually
# showing (an added tab once rendered inside the hidden General panel).
#
# Browser checks are capability-gated like test027: they need Node 22+ and a
# Chrome/Chromium binary (CB_CHROMIUM_PATH, or google-chrome / chromium on PATH).

set -euo pipefail

source ../common--source.sh

NAME="console-tiling-test-$RANDOM"
PORT="$(pick_free_port)"
WORK="$(mktemp -d)"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

CHROME="${CB_CHROMIUM_PATH:-}"
if [[ -z "$CHROME" ]]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$candidate" >/dev/null; then
      CHROME="$(command -v "$candidate")"
      break
    fi
  done
fi
if ! command -v node >/dev/null || ! node -e 'process.exit(typeof WebSocket === "function" ? 0 : 1)' || [[ -z "$CHROME" ]]; then
  echo "SKIP: console tiling browser checks require Node 22+ and Chrome/Chromium (CB_CHROMIUM_PATH may name it)."
  exit 0
fi

# A browser that has never opened this console starts from console.json: the
# 3x2 grid, with pane 5 showing an outside site — the booth itself on
# 127.0.0.1, cross-origin to the console on localhost.
mkdir -p "$WORK/.booth"
cat > "$WORK/.booth/console.json" <<EOF
{ "layout": "grid6", "panes": { "5": { "web": true, "tabs": ["127.0.0.1:$PORT/__booth/health"] } } }
EOF

# console-spec=shared (with .booth/ writable) so the layout saves land in
# .booth/console.json, where the browser cases read them back.
run_coding_booth --variant base --code "$WORK" --name "$NAME" --port "$PORT" --daemon \
  --console-spec shared --writable-booth \
  > "$0.log" 2>&1 || true

wait_ready() {
  local _
  for _ in {1..90}; do
    if [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/__booth/health" || true)" == 200 ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}
if ! wait_ready; then
  print_test_result "false" "$0" "1" "The booth should answer on port $PORT; see $0.log"
  docker logs --tail 20 "$NAME" >&2 || true
  exit 1
fi

ALL=true
CASES=0
OUT=""
browser_phase() {
  OUT="$(CB_CHROME="$CHROME" CB_CASE_START="$CASES" node fixtures/console-tiling/browser.mjs "http://localhost:$PORT/" "$NAME" "$1" 2>&1 || true)"
  local tag number result description
  while IFS='|' read -r tag number result description; do
    if [[ "$tag" != CASE ]]; then
      continue
    fi
    CASES=$((CASES + 1))
    print_test_result "$result" "$0" "$number" "$description"
    if [[ "$result" != true ]]; then
      ALL=false
    fi
  done <<< "$OUT"
  if [[ "$ALL" != true ]]; then
    echo "$OUT" | grep -v '^CASE|' >&2 || true
  fi
}

browser_phase main

# The same booth again with a console.json broken every way the console has
# to survive: an unknown layout, tabs that would end the <script> holding the
# file or swallow the one after it, a tab that is not an address, a pane that
# is not an object, a pane number out of range. It only reads the file at
# start, hence the restart.
cat > "$WORK/.booth/console.json" <<EOF
{ "layout": "Not-A-Layout",
  "panes": {
    "5": { "web": true, "tabs": ["127.0.0.1:$PORT/__booth/health", { "x": 1 }, ":3000/</script>stray<!--<script>"] },
    "2": "oops",
    "9": { "web": true, "tabs": [":3000"] } } }
EOF
docker restart "$NAME" >/dev/null 2>&1 || true
if ! wait_ready; then
  print_test_result "false" "$0" "$((CASES + 1))" "The booth should come back after a restart; see docker logs $NAME"
  exit 1
fi
browser_phase fallback

EXPECTED=19
if [[ "$ALL" != true || "$CASES" -lt "$EXPECTED" ]]; then
  if [[ "$CASES" -lt "$EXPECTED" ]]; then
    print_test_result "false" "$0" "$((CASES + 1))" "Only $CASES of $EXPECTED browser cases reported"
  fi
  exit 1
fi
