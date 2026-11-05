#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: a plain booth starts TTT on zenith with rounded borders
#
# TTT is the base image's default editor, so a booth that selects no ttt template
# still has it. The theme start-up that ttt--setup.sh writes into the image seeds
# theme and editor.borderStyle there; the ttt+theme extension only picks other
# values (tests/complex/boothfile/test-boothfile-ttt). This needs a base image
# built from this tree: an older one has no theme start-up.
#
# Test 1: a booth with no .booth/ gets zenith and rounded
# Test 2: TTT_THEME / TTT_BORDER_STYLE set empty in the container leave both to TTT
#
# Deliberately NOT `set -e`: each check reports what it got instead.
# -------------------------------------------------------

FAILED=0

FIXTURE="$(mktemp -d)"
cleanup() {
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

LOOK='jq -c "[.theme, .editor.borderStyle]" ~/.config/ttt/settings.json 2>/dev/null || echo "<no settings.json>"'

# -------------------------------------------------------
# Test 1: the default look, with nothing selected
# -------------------------------------------------------
OUT="$(run_coding_booth --code "$FIXTURE" --variant base --silence-build -- "$LOOK" 2>&1)" || true
ACTUAL="$(printf '%s\n' "$OUT" | tail -1)"

if [[ "$ACTUAL" == '["zenith","rounded"]' ]]; then
  print_test_result "true" "$0" "1" "A plain booth starts TTT on zenith with rounded borders"
else
  print_test_result "false" "$0" "1" "TTT settings should hold zenith and rounded, got '$ACTUAL'"
  printf '%s\n' "${OUT:-<empty — the booth did not run>}" | tail -5 | sed 's/^/  | /'
  echo "  Hint: '<no settings.json>' or nulls mean the base image predates the theme start-up."
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: the opt-out — empty values in the container
# -------------------------------------------------------
OUT="$(run_coding_booth --code "$FIXTURE" --variant base --silence-build \
         -e TTT_THEME= -e TTT_BORDER_STYLE= -- "$LOOK" 2>&1)" || true
ACTUAL="$(printf '%s\n' "$OUT" | tail -1)"

# ttt-lsp may still write settings.json for servers on PATH; the look must be unset.
if [[ "$ACTUAL" == '<no settings.json>' || "$ACTUAL" == '[null,null]' ]]; then
  print_test_result "true" "$0" "2" "Empty TTT_THEME and TTT_BORDER_STYLE leave the look to TTT"
else
  print_test_result "false" "$0" "2" "Empty values should leave theme and border unset, got '$ACTUAL'"
  printf '%s\n' "${OUT:-<empty — the booth did not run>}" | tail -5 | sed 's/^/  | /'
  FAILED=$((FAILED + 1))
fi

exit $FAILED
