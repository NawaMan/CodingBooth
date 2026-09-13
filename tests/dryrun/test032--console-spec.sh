#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --console-spec / console-spec propagate to the BOOTH_CONSOLE_SPEC
# docker run env var (read by start-ttyd-split to decide whether — and where
# — the base variant console saves its own layout/tabs back to console.json).
#
#   Test 1: --console-spec shared emits BOOTH_CONSOLE_SPEC=shared.
#   Test 2: --console-spec cache emits BOOTH_CONSOLE_SPEC=cache.
#   Test 3: No --console-spec → no BOOTH_CONSOLE_SPEC env var at all.
#   Test 4: TOML key console-spec produces the same env var as the CLI flag.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# ---------------------------------------------------------------------------
# Test 1: --console-spec shared
# ---------------------------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --dryrun --console-spec shared 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF "BOOTH_CONSOLE_SPEC=shared"; then
  print_test_result "true" "$0" "1" "--console-spec shared emits BOOTH_CONSOLE_SPEC=shared"
else
  print_test_result "false" "$0" "1" "--console-spec shared missing BOOTH_CONSOLE_SPEC"
  echo "  BOOTH_CONSOLE_SPEC lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_CONSOLE_SPEC" || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Test 2: --console-spec cache
# ---------------------------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --dryrun --console-spec cache 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF "BOOTH_CONSOLE_SPEC=cache"; then
  print_test_result "true" "$0" "2" "--console-spec cache emits BOOTH_CONSOLE_SPEC=cache"
else
  print_test_result "false" "$0" "2" "--console-spec cache missing BOOTH_CONSOLE_SPEC"
  echo "  BOOTH_CONSOLE_SPEC lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_CONSOLE_SPEC" || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Test 3: No --console-spec → no BOOTH_CONSOLE_SPEC env var at all
# ---------------------------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --dryrun 2>/dev/null | strip_ansi)

if ! echo "$ACTUAL" | grep -qF "BOOTH_CONSOLE_SPEC"; then
  print_test_result "true" "$0" "3" "No --console-spec → no BOOTH_CONSOLE_SPEC env var injected"
else
  print_test_result "false" "$0" "3" "BOOTH_CONSOLE_SPEC leaked into a run with no --console-spec"
  echo "  BOOTH_CONSOLE_SPEC lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_CONSOLE_SPEC"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Test 4: TOML console-spec key produces the same env var
# ---------------------------------------------------------------------------
CFG=test--console-spec-config.toml
cat > "$CFG" <<'EOF'
variant = "base"
console-spec = "shared"
EOF

ACTUAL=$(run_coding_booth --config "$CFG" --dryrun 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF "BOOTH_CONSOLE_SPEC=shared"; then
  print_test_result "true" "$0" "4" "TOML console-spec key propagates to BOOTH_CONSOLE_SPEC"
else
  print_test_result "false" "$0" "4" "TOML console-spec key did not propagate as expected"
  echo "  BOOTH_CONSOLE_SPEC lines in dryrun:"
  echo "$ACTUAL" | grep -E "BOOTH_CONSOLE_SPEC" || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

rm -f "$CFG"

exit $FAILED
