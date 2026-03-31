#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: +port syntax in --expose / run-args
#
# Verifies that +OFFSET port mappings in run-args are resolved to absolute
# ports based on the booth port at runtime.
#
# Test 1: +8080:8080 with default port (10000) → -p 18080:8080
# Test 2: +3000:3000 with explicit port (12000) → -p 15000:3000
# Test 3: Plain port is unchanged (8080:8080 stays 8080:8080)
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# Test 1: +8080:8080 with default booth port (10000 in dryrun) → -p 18080:8080
printf 'variant = "base"\nrun-args = ["-p", "+8080:8080"]\n' > test--plus-port-config1.toml

ACTUAL=$(run_coding_booth --config test--plus-port-config1.toml --dryrun -- echo test 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF -- "-p 18080:8080"; then
  print_test_result "true" "$0" "1" "+8080:8080 resolved to 18080:8080 with default port"
else
  print_test_result "false" "$0" "1" "+8080:8080 should resolve to 18080:8080"
  echo "  Actual output (grep for -p):"
  echo "$ACTUAL" | grep -- "-p"
  FAILED=$((FAILED + 1))
fi

rm -f test--plus-port-config1.toml

# Test 2: +3000:3000 with explicit port 12000 → -p 15000:3000
printf 'variant = "base"\nport = "12000"\nrun-args = ["-p", "+3000:3000"]\n' > test--plus-port-config2.toml

ACTUAL=$(run_coding_booth --config test--plus-port-config2.toml --dryrun -- echo test 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF -- "-p 15000:3000"; then
  print_test_result "true" "$0" "2" "+3000:3000 with port 12000 resolved to 15000:3000"
else
  print_test_result "false" "$0" "2" "+3000:3000 with port 12000 should resolve to 15000:3000"
  echo "  Actual output (grep for -p):"
  echo "$ACTUAL" | grep -- "-p"
  FAILED=$((FAILED + 1))
fi

rm -f test--plus-port-config2.toml

# Test 3: Plain port mapping is unchanged
printf 'variant = "base"\nrun-args = ["-p", "8080:8080"]\n' > test--plus-port-config3.toml

ACTUAL=$(run_coding_booth --config test--plus-port-config3.toml --dryrun -- echo test 2>/dev/null | strip_ansi)

if echo "$ACTUAL" | grep -qF -- "-p 8080:8080"; then
  print_test_result "true" "$0" "3" "Plain 8080:8080 unchanged"
else
  print_test_result "false" "$0" "3" "Plain 8080:8080 should remain unchanged"
  echo "  Actual output (grep for -p):"
  echo "$ACTUAL" | grep -- "-p"
  FAILED=$((FAILED + 1))
fi

rm -f test--plus-port-config3.toml

exit $FAILED
