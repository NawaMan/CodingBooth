#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --idle-time / --idle-exit-code propagate to docker run env vars
#
# Verifies the wiring between the host CLI and the in-container idle monitor:
#
#   Test 1: --idle-time 30,45 --idle-exit-code 7 emits all three env vars
#           with exact values.
#   Test 2: --idle-time 120 alone uses defaults (SHUTDOWN_TIME=60, EXIT_CODE=0).
#   Test 3: No --idle-time → no BOOTH_IDLE_* env vars at all.
#   Test 4: TOML keys (idle-time / idle-shutdown-time / idle-exit-code)
#           produce the same env vars as the CLI flags.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# ---------------------------------------------------------------------------
# Test 1: --idle-time s,t --idle-exit-code n
# ---------------------------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --dryrun \
           --idle-time 30,45 --idle-exit-code 7 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF "BOOTH_IDLE_TIME=30" \
   && echo "$ACTUAL" | grep -qF "BOOTH_IDLE_SHUTDOWN_TIME=45" \
   && echo "$ACTUAL" | grep -qF "BOOTH_IDLE_EXIT_CODE=7"; then
  print_test_result "true" "$0" "1" "--idle-time 30,45 --idle-exit-code 7 emits all three env vars"
else
  print_test_result "false" "$0" "1" "--idle-time 30,45 --idle-exit-code 7 missing env vars"
  echo "  BOOTH_IDLE lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_IDLE" || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Test 2: --idle-time s (no shutdown time, no exit code) → defaults
# ---------------------------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --dryrun --idle-time 120 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF "BOOTH_IDLE_TIME=120" \
   && echo "$ACTUAL" | grep -qF "BOOTH_IDLE_SHUTDOWN_TIME=60" \
   && echo "$ACTUAL" | grep -qF "BOOTH_IDLE_EXIT_CODE=0"; then
  print_test_result "true" "$0" "2" "--idle-time 120 uses SHUTDOWN_TIME=60 and EXIT_CODE=0 defaults"
else
  print_test_result "false" "$0" "2" "--idle-time 120 default SHUTDOWN_TIME/EXIT_CODE mismatch"
  echo "  BOOTH_IDLE lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_IDLE" || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Test 3: No --idle-time → no BOOTH_IDLE_* env vars at all
# ---------------------------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --dryrun 2>/dev/null | strip_ansi)

if ! echo "$ACTUAL" | grep -qE "BOOTH_IDLE_"; then
  print_test_result "true" "$0" "3" "No --idle-time → no BOOTH_IDLE_* env vars injected"
else
  print_test_result "false" "$0" "3" "BOOTH_IDLE_* env vars leaked into non-idle run"
  echo "  BOOTH_IDLE lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_IDLE"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Test 4: TOML config keys produce the same env vars
# ---------------------------------------------------------------------------
CFG=test--idle-config.toml
cat > "$CFG" <<'EOF'
variant = "base"
idle-time = 90
idle-shutdown-time = 20
idle-exit-code = 3
EOF

ACTUAL=$(run_coding_booth --config "$CFG" --dryrun 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF "BOOTH_IDLE_TIME=90" \
   && echo "$ACTUAL" | grep -qF "BOOTH_IDLE_SHUTDOWN_TIME=20" \
   && echo "$ACTUAL" | grep -qF "BOOTH_IDLE_EXIT_CODE=3"; then
  print_test_result "true" "$0" "4" "TOML idle-* keys propagate to BOOTH_IDLE_* env vars"
else
  print_test_result "false" "$0" "4" "TOML idle-* keys did not propagate as expected"
  echo "  BOOTH_IDLE lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_IDLE" || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

rm -f "$CFG"

# ---------------------------------------------------------------------------
# Test 5: bad --idle-time value prints a clean error (no Go stack trace)
# ---------------------------------------------------------------------------
# Not using run_coding_booth here because we want to capture the non-zero exit
# and stderr without the wrapper's stdout tee getting in the way.
BINARY=""
for d in "../.." "../../.." "../../../.." "../../../../.."; do
  if [[ -x "$d/codingbooth" ]]; then BINARY="$d/codingbooth"; break; fi
done

if [[ -z "$BINARY" ]]; then
  print_test_result "false" "$0" "5" "Could not locate codingbooth binary for error-path test"
  FAILED=$((FAILED + 1))
else
  OUT=$("$BINARY" --variant base --dryrun --idle-time abc 2>&1 || true)
  EC=$("$BINARY" --variant base --dryrun --idle-time abc >/dev/null 2>&1; echo $?)

  if [[ "$EC" == "2" ]] \
     && echo "$OUT" | grep -qF -- '--idle-time requires a positive integer' \
     && ! echo "$OUT" | grep -qE 'panic:|goroutine [0-9]+ \[running\]'; then
    print_test_result "true" "$0" "5" "--idle-time abc → friendly error, no stack trace"
  else
    print_test_result "false" "$0" "5" "--idle-time abc did not produce a clean error (exit=$EC)"
    echo "  Output:"
    echo "$OUT" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi

  # Test 6: bad shutdown-time part (--idle-time 30,0)
  OUT=$("$BINARY" --variant base --dryrun --idle-time 30,0 2>&1 || true)
  if echo "$OUT" | grep -qF -- '--idle-time shutdown time requires a positive integer' \
     && ! echo "$OUT" | grep -qE 'panic:|goroutine [0-9]+ \[running\]'; then
    print_test_result "true" "$0" "6" "--idle-time 30,0 → friendly error, no stack trace"
  else
    print_test_result "false" "$0" "6" "--idle-time 30,0 did not produce a clean error"
    echo "  Output:"
    echo "$OUT" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
fi

exit $FAILED
