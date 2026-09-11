#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the base variant's web terminal (ttyd) actually renders the Fira Code
# Nerd Font — not just names it.
#
# ttyd's terminal renders in the *visitor's browser* via canvas/WebGL, not in
# this container, so installing the font system-wide
# (fira-code-nerd-font--setup.sh) and passing `-t fontFamily=...` names a font
# without supplying one — a visitor whose browser never had that family
# installed would silently fall back to its own default monospace. This was
# shipped once and looked fine under `docker exec` + `ps` checks, but a real
# browser never actually got the glyphs (see PR discussion). The fix has two
# halves that both have to be tested with `--compressed`, the same as a real
# browser's default `Accept-Encoding: gzip` — plain curl doesn't send that,
# and nginx's `sub_filter` silently no-ops on a compressed body, so a test
# using plain curl would pass while the real bug (still) reproduces:
#   - split mode (default): start-ttyd-split's nginx layer serves the font as
#     a real cached asset at /booth-assets/fonts/ and `sub_filter`-injects an
#     @font-face referencing it into every pane's HTML.
#   - non-split mode (BOOTH_WEB_SPLIT=false): no nginx sits in front, so
#     ttyd-nerd-font-index--setup.sh bakes a custom ttyd index.html with the
#     font embedded as a data URI, handed to `ttyd -I`.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME1="ttyd-font-split-$RANDOM"
NAME2="ttyd-font-nosplit-$RANDOM"
PORT1="$(pick_free_port)"
PORT2="$(pick_free_port_other_than "$PORT1")"

cleanup() {
  docker stop "$NAME1" "$NAME2" >/dev/null 2>&1 || true
  docker rm   "$NAME1" "$NAME2" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_200() {
  local url="$1"
  for i in {1..40}; do
    if curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q 200; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_coding_booth --variant base --name "$NAME1" --port "$PORT1" --daemon > "$0.split.log" 2>&1
run_coding_booth --variant base --name "$NAME2" --port "$PORT2" -e BOOTH_WEB_SPLIT=false --daemon > "$0.nosplit.log" 2>&1

# Split mode has an nginx health endpoint; the non-split fallback is bare
# ttyd with no such route, so its readiness is just "the root page answers".
if ! wait_for_200 "http://127.0.0.1:${PORT1}/__booth/health"; then
  print_test_result "false" "$0" "0" "Booth '$NAME1' (split) never answered /__booth/health"
  docker logs "$NAME1" 2>&1 | tail -30 >&2
  exit 1
fi

if ! wait_for_200 "http://127.0.0.1:${PORT2}/"; then
  print_test_result "false" "$0" "0" "Booth '$NAME2' (non-split) never answered on its root page"
  docker logs "$NAME2" 2>&1 | tail -30 >&2
  exit 1
fi

# -------------------------------------------------------
# Test 1: the font file ships in the base image
# -------------------------------------------------------
ACTUAL=$(docker exec "$NAME1" test -f /usr/share/fonts/truetype/fira-code-nerd-font/FiraCodeNerdFontMono-Regular.ttf && echo present || echo missing)

if [[ "$ACTUAL" == "present" ]]; then
  print_test_result "true" "$0" "1" "Fira Code Nerd Font Mono ships in the base image"
else
  print_test_result "false" "$0" "1" "Fira Code Nerd Font Mono ships in the base image"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: a real browser's request (gzip'd) to a split-mode pane gets the
# @font-face style — the exact case plain curl would miss and falsely pass
# -------------------------------------------------------
PANE_HTML=$(curl -s --compressed "http://127.0.0.1:${PORT1}/s1/")

if [[ "$PANE_HTML" == *"@font-face"* && "$PANE_HTML" == *"FiraCode Nerd Font Mono"* ]]; then
  print_test_result "true" "$0" "2" "split-mode pane /s1/ carries the @font-face style even when gzip'd"
else
  print_test_result "false" "$0" "2" "split-mode pane /s1/ should carry the @font-face style when gzip'd"
  echo "  First 300 chars of response: ${PANE_HTML:0:300}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the font referenced by that style is actually fetchable
# -------------------------------------------------------
FONT_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT1}/booth-assets/fonts/FiraCodeNerdFontMono-Regular.ttf")

if [[ "$FONT_CODE" == "200" ]]; then
  print_test_result "true" "$0" "3" "/booth-assets/fonts/ serves the referenced font file (200)"
else
  print_test_result "false" "$0" "3" "/booth-assets/fonts/ should serve the font file (200)"
  echo "  Actual status: $FONT_CODE"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 4: the non-split fallback (no nginx in front) embeds the font directly
# -------------------------------------------------------
ROOT_HTML=$(curl -s --compressed "http://127.0.0.1:${PORT2}/")

if [[ "$ROOT_HTML" == *"@font-face"* && "$ROOT_HTML" == *"FiraCode Nerd Font Mono"* && "$ROOT_HTML" == *"data:font/ttf;base64,"* ]]; then
  print_test_result "true" "$0" "4" "non-split root page embeds the font as a data URI even when gzip'd"
else
  print_test_result "false" "$0" "4" "non-split root page should embed the font as a data URI when gzip'd"
  echo "  First 300 chars of response: ${ROOT_HTML:0:300}"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
