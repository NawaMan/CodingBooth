#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: lazygit ships in the base image
#
# lazygit is installed by variants/base/setups/lazygit--setup.sh from the
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
# Test 1: lazygit is on PATH
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'command -v lazygit' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "/usr/local/bin/lazygit" ]]; then
  print_test_result "true" "$0" "1" "lazygit is installed in the base image"
else
  print_test_result "false" "$0" "1" "lazygit is installed in the base image"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  echo "  Hint: the base image must carry lazygit. If a locally-built image has"
  echo "        taken the ${CB_PREBUILD_REPO:-nawaman/codingbooth} tag, re-pull it."
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: lazygit runs and reports a version
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'lazygit --version' 2>&1 | tail -1) || ACTUAL=""

if echo "$ACTUAL" | grep -qE 'version=[0-9]+\.[0-9]+'; then
  print_test_result "true" "$0" "2" "lazygit reports a version ($ACTUAL)"
else
  print_test_result "false" "$0" "2" "lazygit reports a version"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the welcome message lists lazygit
#
# The welcome only prints for an interactive login shell, and the outer
# `bash -lc` booth runs commands with is not interactive — so it never sets
# TIP_SHOWN and the inner `bash -lic` prints the banner.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'bash -lic true 2>/dev/null | grep -c "^  lazygit "' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "3" "welcome message lists lazygit"
else
  print_test_result "false" "$0" "3" "welcome message lists lazygit"
  echo "  Matching welcome lines: ${ACTUAL:-<empty — the booth did not run>} (want 1)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 4: lazygit actually runs
#
# --version proves the file is executable; this proves it is lazygit. The
# UI needs a TTY, so we cannot drive a staging session; `lazygit --config`
# is a real command path that dumps the default config without a terminal.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- \
  'lazygit --config 2>/dev/null | grep -c "^gui:"' \
  2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "4" "lazygit prints its default config"
else
  print_test_result "false" "$0" "4" "lazygit prints its default config"
  echo "  Matching config sections: ${ACTUAL:-<empty — the booth did not run>} (want 1)"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
