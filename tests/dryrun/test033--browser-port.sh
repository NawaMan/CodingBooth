#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --browser-port's validation.
#
# --browser-port picks which port --browser opens, instead of the booth's own
# port: an absolute number, or a "+OFFSET" counted from the offset base (see
# --offset-base, tests/dryrun/test030--offset-base.sh) — the same arithmetic a
# "+OFFSET" run-arg uses, so a dev server published via "-p +80:8080" can be
# opened with "--browser-port +80" instead of restating the resolved port.
#
# Resolving to a port never shows up in the docker command line dryrun prints
# (it only feeds the browser-open URL, at run time, not build time), so there
# is nothing positive to grep for here. The positive path — a booth on port
# 24000 with --browser-port +80 opening 24080 — is covered by a real booth in
# tests/basic/test019--browser-open.sh (cases 9-10) and by Go unit tests
# (TestParseBrowserPort, TestBrowserOpenURL). This file covers what dryrun
# alone can: --browser-port's validation errors, printed to stderr and exiting
# non-zero before a container would ever be considered.
#
# Test 1: --browser-port abc      → rejected (must be a number or +OFFSET)
# Test 2: --browser-port +abc     → rejected (+OFFSET must be a number)
# Test 3: --browser-port 70000    → rejected (out of range)
# Test 4: --browser-port +70000   → rejected once resolved (offset-base
#                                    defaults to the booth port, 20000, so
#                                    +70000 resolves to 90000)
# Test 5: --browser-port -1       → rejected (out of range)
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# Test 1: a non-numeric absolute value is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 --browser-port abc -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--browser-port must be a number or +OFFSET'; then
  print_test_result "true" "$0" "1" "--browser-port abc is rejected (must be a number or +OFFSET)"
else
  print_test_result "false" "$0" "1" "--browser-port abc should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

# Test 2: a non-numeric +OFFSET is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 --browser-port +abc -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--browser-port +OFFSET must be a number'; then
  print_test_result "true" "$0" "2" "--browser-port +abc is rejected (+OFFSET must be a number)"
else
  print_test_result "false" "$0" "2" "--browser-port +abc should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

# Test 3: an out-of-range absolute port is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 --browser-port 70000 -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--browser-port must be between 1 and 65535'; then
  print_test_result "true" "$0" "3" "--browser-port 70000 is rejected (out of range)"
else
  print_test_result "false" "$0" "3" "--browser-port 70000 should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

# Test 4: a +OFFSET that resolves out of range is rejected once resolved, not
# on the offset itself — offset-base defaults to the booth port (20000 here),
# so +70000 resolves to 90000.
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 --browser-port +70000 -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- 'resolves to 90000, which is outside 1-65535'; then
  print_test_result "true" "$0" "4" "--browser-port +70000 is rejected once resolved to 90000"
else
  print_test_result "false" "$0" "4" "--browser-port +70000 should be rejected once resolved to 90000"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

# Test 5: a negative absolute port is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 --browser-port -1 -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--browser-port must be between 1 and 65535'; then
  print_test_result "true" "$0" "5" "--browser-port -1 is rejected (out of range)"
else
  print_test_result "false" "$0" "5" "--browser-port -1 should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

exit $FAILED
