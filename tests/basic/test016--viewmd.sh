#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: viewmd (MarkDownViewer) ships in the base image
#
# viewmd is installed by variants/base/setups/viewmd--setup.sh from the
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
# Test 1: viewmd is on PATH
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'command -v viewmd' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "/usr/local/bin/viewmd" ]]; then
  print_test_result "true" "$0" "1" "viewmd is installed in the base image"
else
  print_test_result "false" "$0" "1" "viewmd is installed in the base image"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  echo "  Hint: the base image must carry viewmd. If a locally-built image has"
  echo "        taken the ${CB_PREBUILD_REPO:-nawaman/codingbooth} tag, re-pull it."
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: viewmd runs and reports a version
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'viewmd version' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  print_test_result "true" "$0" "2" "viewmd reports a version ($ACTUAL)"
else
  print_test_result "false" "$0" "2" "viewmd reports a version"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the welcome message lists viewmd
#
# The welcome only prints for an interactive login shell, and the outer
# `bash -lc` booth runs commands with is not interactive — so it never sets
# TIP_SHOWN and the inner `bash -lic` prints the banner.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'bash -lic true 2>/dev/null | grep -c "^  viewmd "' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "3" "welcome message lists viewmd"
else
  print_test_result "false" "$0" "3" "welcome message lists viewmd"
  echo "  Matching welcome lines: ${ACTUAL:-<empty — the booth did not run>} (want 1)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 4: viewmd actually serves Markdown
#
# --version proves the file is executable; this proves it works. Serves the
# in-image docs folder, then stops the daemon again.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- \
  'viewmd --folder /opt/codingbooth/docs --daemon >/dev/null 2>&1; curl -fsS -o /dev/null -w "SERVE=%{http_code}\n" http://127.0.0.1:8765/ || echo SERVE=FAILED; viewmd stop >/dev/null 2>&1' \
  2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "SERVE=200" ]]; then
  print_test_result "true" "$0" "4" "viewmd serves a folder of Markdown files"
else
  print_test_result "false" "$0" "4" "viewmd serves a folder of Markdown files"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
