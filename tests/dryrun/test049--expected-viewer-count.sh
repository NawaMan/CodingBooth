#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: expected-viewer-count reaches the booth as BOOTH_EXPECTED_VIEWER_COUNT
#
# The Booth panel shows the viewer count only above this many viewers. The
# value is always passed, so it can be read inside the booth with echo.
#
#   Test 1: Nothing set → BOOTH_EXPECTED_VIEWER_COUNT=1.
#   Test 2: --expected-viewer-count 3 → 3; 0 is kept, not dropped as unset.
#   Test 3: config.toml expected-viewer-count and CB_EXPECTED_VIEWER_COUNT
#           both reach it, and the flag beats config.toml.
#   Test 4: A negative or non-numeric value is refused with a clean error.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }
expected_of() { grep -oE 'BOOTH_EXPECTED_VIEWER_COUNT=[^ '"'"'"]*' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

FAILED=0
check() {
  local num="$1" desc="$2" got="$3" want="$4"
  if [[ "$got" == "$want" ]]; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc"
    echo "  want: $want"
    echo "  got:  ${got:-(none)}"
    FAILED=$((FAILED + 1))
  fi
}

# ---- Test 1: the default ----
GOT=$(env -u CB_EXPECTED_VIEWER_COUNT "$(find_local_booth_build)" --variant base --dryrun 2>/dev/null | strip_ansi | expected_of)
check 1 "Nothing set → BOOTH_EXPECTED_VIEWER_COUNT=1" "$GOT" "BOOTH_EXPECTED_VIEWER_COUNT=1"

# ---- Test 2: the flag, including 0 ----
GOT3=$(run_coding_booth --variant base --dryrun --expected-viewer-count 3 2>/dev/null | strip_ansi | expected_of)
GOT0=$(run_coding_booth --variant base --dryrun --expected-viewer-count 0 2>/dev/null | strip_ansi | expected_of)
check 2 "--expected-viewer-count 3 and 0 pass through as given" "$GOT3 / $GOT0" \
  "BOOTH_EXPECTED_VIEWER_COUNT=3 / BOOTH_EXPECTED_VIEWER_COUNT=0"

# ---- Test 3: config.toml, the env var, and the flag over config.toml ----
CFG=test--expected-viewer-config.toml
trap 'rm -f "$CFG"' EXIT
printf 'variant = "base"\nexpected-viewer-count = 2\n' > "$CFG"
GOT_CFG=$(run_coding_booth --config "$CFG" --dryrun 2>/dev/null | strip_ansi | expected_of)
GOT_ENV=$(CB_EXPECTED_VIEWER_COUNT=5 run_coding_booth --variant base --dryrun 2>/dev/null | strip_ansi | expected_of)
GOT_FLAG=$(run_coding_booth --config "$CFG" --dryrun --expected-viewer-count 4 2>/dev/null | strip_ansi | expected_of)
check 3 "config.toml and CB_EXPECTED_VIEWER_COUNT reach it; the flag beats config.toml" \
  "$GOT_CFG / $GOT_ENV / $GOT_FLAG" \
  "BOOTH_EXPECTED_VIEWER_COUNT=2 / BOOTH_EXPECTED_VIEWER_COUNT=5 / BOOTH_EXPECTED_VIEWER_COUNT=4"

# ---- Test 4: bad values are refused without a stack trace ----
BINARY="$(find_local_booth_build)" || BINARY=""
printf 'variant = "base"\nexpected-viewer-count = -1\n' > "$CFG"
OUT_FLAG=$("$BINARY" --variant base --dryrun --expected-viewer-count -1 2>&1 || true)
OUT_WORD=$("$BINARY" --variant base --dryrun --expected-viewer-count two 2>&1 || true)
OUT_CFG=$("$BINARY" --config "$CFG" --dryrun 2>&1 || true)
if grep -qF -- '--expected-viewer-count requires a non-negative integer, got "-1"' <<< "$OUT_FLAG" \
   && grep -qF -- '--expected-viewer-count requires a non-negative integer, got "two"' <<< "$OUT_WORD" \
   && grep -qF 'expected-viewer-count must be 0 or more, got -1' <<< "$OUT_CFG" \
   && ! grep -qE 'goroutine [0-9]+ \[running\]' <<< "$OUT_FLAG$OUT_WORD$OUT_CFG"; then
  print_test_result "true" "$0" "4" "Negative or non-numeric values (flag and config.toml) → clean error"
else
  print_test_result "false" "$0" "4" "Negative or non-numeric values (flag and config.toml) → clean error"
  printf '  flag: %s\n  word: %s\n  cfg:  %s\n' "$OUT_FLAG" "$OUT_WORD" "$OUT_CFG"
  FAILED=$((FAILED + 1))
fi

[[ "$FAILED" -eq 0 ]] || exit 1
