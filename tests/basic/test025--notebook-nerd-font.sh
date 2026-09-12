#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the notebook variant's JupyterLab renders the Fira Code Nerd Font, in
# both its terminal and its file/notebook editors.
#
# JupyterLab is wrapped by the same shared generic nginx layer as code-server
# (booth-message-wrapper--setup.sh's start-booth-wrapped) — but its real UI
# lives at /lab (and nested paths under it), not the bare root, so the fix had
# to extend the wrapper's catch-all `location /` (not just the exact-match
# `location = /` code-server uses) with the same Accept-Encoding fix and
# sub_filter injection tests/basic/test024--codeserver-terminal.sh already
# covers, plus nginx's own gzip so disabling Accept-Encoding to the upstream
# broadly doesn't cost bandwidth to the actual browser.
#
# start-notebook-wrapped sets WRAPPER_HEAD_INJECT to an @font-face style plus
# a `:root{--jp-code-font-family:...!important}` override — !important
# because JupyterLab's own theme CSS sets the same variable and loads after
# the injected style (same specificity, last one wins without it). That
# variable is what CodeMirror-based editors (file editor, notebook cells)
# read live, but JupyterLab's terminal is xterm.js rendered via canvas and
# resolves its font once at construction from an explicit settings key
# instead — confirmed the hard way, by finding the CSS-only version of this
# fix left the terminal unchanged in a real browser. notebook--setup.sh's
# startup script pre-seeds that terminal-extension setting (and the matching
# fileeditor-extension one) the first time the booth starts, the same
# "write only if missing" pattern already used to seed the JupyterLab theme.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME="notebook-nerd-font-$RANDOM"
PORT="$(pick_free_port)"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_200() {
  local url="$1"
  for i in {1..60}; do
    if curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q 200; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_coding_booth --variant notebook --name "$NAME" --port "$PORT" --daemon > "$0.log" 2>&1

if ! wait_for_200 "http://127.0.0.1:${PORT}/__booth/health"; then
  print_test_result "false" "$0" "0" "Booth '$NAME' never answered /__booth/health"
  docker logs "$NAME" 2>&1 | tail -30 >&2
  exit 1
fi

# JupyterLab itself can take a moment to come up behind the wrapper even
# after the wrapper's own health check is green.
for i in {1..30}; do
  CODE=$(curl -sL -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/lab?_booth_inner=1" 2>/dev/null)
  [[ "$CODE" == "200" ]] && break
  sleep 1
done

# -------------------------------------------------------
# Test 1: the wrapped /lab document carries the @font-face style even when
# gzip'd — the exact case plain curl would miss and falsely pass
# -------------------------------------------------------
LAB_HTML=$(curl -sL --compressed "http://127.0.0.1:${PORT}/lab?_booth_inner=1")

if [[ "$LAB_HTML" == *"@font-face"* && "$LAB_HTML" == *"FiraCode Nerd Font Mono"* ]]; then
  print_test_result "true" "$0" "1" "wrapped /lab document carries the @font-face style even when gzip'd"
else
  print_test_result "false" "$0" "1" "wrapped /lab document should carry the @font-face style when gzip'd"
  echo "  First 300 chars of response: ${LAB_HTML:0:300}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: the font referenced by that style — the .woff2, not the .ttf; the
# browser downloads whichever the @font-face src actually names — is
# actually fetchable
# -------------------------------------------------------
FONT_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/booth-assets/fonts/FiraCodeNerdFontMono-Regular.woff2")

if [[ "$FONT_CODE" == "200" ]]; then
  print_test_result "true" "$0" "2" "/booth-assets/fonts/ serves the referenced .woff2 font file (200)"
else
  print_test_result "false" "$0" "2" "/booth-assets/fonts/ should serve the referenced .woff2 font file (200)"
  echo "  Actual status: $FONT_CODE"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the terminal extension's own explicit font setting is seeded.
# The @font-face + CSS variable alone do NOT change the terminal's actual
# rendering (xterm.js resolves its font once at construction, not live from
# CSS) — only this explicit settings key does.
# -------------------------------------------------------
TERM_SETTINGS=$(docker exec "$NAME" su - coder -c 'cat ~/.jupyter/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings' 2>/dev/null)

if [[ "$TERM_SETTINGS" == *"FiraCode Nerd Font Mono"* ]]; then
  print_test_result "true" "$0" "3" "terminal-extension's own settings file carries the font"
else
  print_test_result "false" "$0" "3" "terminal-extension's own settings file should carry the font"
  echo "  File contents: ${TERM_SETTINGS:-<missing>}"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
