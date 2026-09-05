#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: just ships in the base image
#
# just is installed by variants/base/setups/just--setup.sh from the
# Dockerfile, so every variant inherits it. It is also advertised in the login
# welcome message — a tool nobody is told about is a tool nobody uses, so the
# welcome line is guarded here too.
#
# Deliberately NOT `set -e`: a booth that fails to start makes every capture
# below empty, and under `set -e` the script would die on the first one having
# printed nothing at all — no failing assertion, no output, nothing to debug
# from. Each check reports what it actually got instead.
# -------------------------------------------------------

FAILED=0

# -------------------------------------------------------
# Test 1: just is on PATH
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'command -v just' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "/usr/local/bin/just" ]]; then
  print_test_result "true" "$0" "1" "just is installed in the base image"
else
  print_test_result "false" "$0" "1" "just is installed in the base image"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  echo "  Hint: the base image must carry just. If a locally-built image has"
  echo "        taken the ${CB_PREBUILD_REPO:-nawaman/codingbooth} tag, re-pull it."
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: just runs and reports a version
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'just --version' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" =~ ^just\ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
  print_test_result "true" "$0" "2" "just reports a version ($ACTUAL)"
else
  print_test_result "false" "$0" "2" "just reports a version"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the welcome message lists just
#
# The welcome only prints for an interactive login shell, and the outer
# `bash -lc` booth runs commands with is not interactive — so it never sets
# TIP_SHOWN and the inner `bash -lic` prints the banner.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'bash -lic true 2>/dev/null | grep -c "^  just "' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "3" "welcome message lists just"
else
  print_test_result "false" "$0" "3" "welcome message lists just"
  echo "  Matching welcome lines: ${ACTUAL:-<empty — the booth did not run>} (want 1)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 4: just actually runs a recipe
#
# --version proves the file is executable; this proves it works. Writes a
# justfile and runs a recipe that prints a known string.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- \
  'd=$(mktemp -d) && printf "proof:\n    @echo JUST_OK\n" > "$d/justfile" && just --justfile "$d/justfile" proof' \
  2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "JUST_OK" ]]; then
  print_test_result "true" "$0" "4" "just runs a recipe from a justfile"
else
  print_test_result "false" "$0" "4" "just runs a recipe from a justfile"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
