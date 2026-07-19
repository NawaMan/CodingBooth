#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --port NEXT / RANDOM accept an optional ":base" starting point.
#
# NEXT / RANDOM used to always scan from 10000; a ":base" suffix moves the start.
# In dryrun mode the scan is short-circuited to the base (no sockets bound), so the
# selected host port is deterministic and equals the base.
#
# NOTE: dryrun deliberately does not bind sockets, so it cannot exercise the live
# "skip the occupied port and advance" behavior. That is covered by the Go unit
# tests (TestFindNextPort_SkipsOccupied / TestFindRandomPort_AvoidsOccupiedBase in
# pkg/booth/port_determination_test.go) and end-to-end by
# tests/complex/test-port-next-skip.
#
# Test 1: NEXT:20000   → host port 20000 published to container 10000
# Test 2: RANDOM:30000 → host port 30000
# Test 3: NEXT         → unchanged default of 10000
# Test 4: NEXT:abc     → rejected (base must be a number)
# Test 5: NEXT:70000   → rejected (base out of range)
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# Test 1: NEXT:20000 → 20000
ACTUAL=$(run_coding_booth --dryrun --variant base --port NEXT:20000 -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 127.0.0.1:20000:10000' \
   && echo "$ACTUAL" | grep -qF -- "BOOTH_HOST_PORT=20000"; then
  print_test_result "true" "$0" "1" "NEXT:20000 selects host port 20000"
else
  print_test_result "false" "$0" "1" "NEXT:20000 should select host port 20000"
  echo "$ACTUAL" | grep -iE 'host_port|127.0.0.1' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 2: RANDOM:30000 → 30000 (dryrun short-circuits to base, so it is deterministic)
ACTUAL=$(run_coding_booth --dryrun --variant base --port RANDOM:30000 -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 127.0.0.1:30000:10000'; then
  print_test_result "true" "$0" "2" "RANDOM:30000 selects host port 30000"
else
  print_test_result "false" "$0" "2" "RANDOM:30000 should select host port 30000"
  echo "$ACTUAL" | grep -iE '127.0.0.1' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 3: bare NEXT still starts at the 10000 default
ACTUAL=$(run_coding_booth --dryrun --variant base --port NEXT -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 127.0.0.1:10000:10000'; then
  print_test_result "true" "$0" "3" "bare NEXT still defaults to base 10000"
else
  print_test_result "false" "$0" "3" "bare NEXT should default to base 10000"
  echo "$ACTUAL" | grep -iE '127.0.0.1' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 4: a non-numeric base is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --port NEXT:abc -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- 'base must be a number'; then
  print_test_result "true" "$0" "4" "NEXT:abc is rejected (base must be a number)"
else
  print_test_result "false" "$0" "4" "NEXT:abc should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

# Test 5: an out-of-range base is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --port NEXT:70000 -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- 'base must be between 1 and 65535'; then
  print_test_result "true" "$0" "5" "NEXT:70000 is rejected (base out of range)"
else
  print_test_result "false" "$0" "5" "NEXT:70000 should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

exit $FAILED
