#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: the Console UI's i3-style Ctrl+Alt tiling and its CodingBooth Help, in
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

run_coding_booth --variant base --code "$WORK" --name "$NAME" --port "$PORT" --daemon \
  > "$0.log" 2>&1 || true

ready=false
for _ in {1..90}; do
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/__booth/health" || true)" == 200 ]]; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  print_test_result "false" "$0" "1" "The booth should answer on port $PORT; see $0.log"
  docker logs --tail 20 "$NAME" >&2 || true
  exit 1
fi

OUT="$(CB_CHROME="$CHROME" node fixtures/console-tiling/browser.mjs "http://localhost:$PORT/" "$NAME" 2>&1 || true)"
ALL=true
CASES=0
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

if [[ "$ALL" != true || "$CASES" -lt 6 ]]; then
  echo "$OUT" | grep -v '^CASE|' >&2 || true
  if [[ "$CASES" -lt 6 ]]; then
    print_test_result "false" "$0" "$((CASES + 1))" "Only $CASES of 6 browser cases reported"
  fi
  exit 1
fi
