#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the user's command reaches `bash -lc` as ONE string, in every run mode.
#
# `--` takes command words and runs them with `bash -lc` (see `booth --help`),
# which takes a single command string and treats anything after it as $0, $1,
# ... So the words have to be joined before they are handed over.
#
# The daemon path appended them as separate arguments instead, so
# `--daemon -- sleep 600` ran `bash -lc sleep 600`: the script was "sleep",
# with "600" as its $0, and the booth's command died on "sleep: missing
# operand". In daemon mode the container stays up on the booth's own services,
# so nothing but a line in `docker logs` said the command never ran — and the
# basic tests that use this form assert only the container's lifecycle.
#
# Test 1: command mode joins the words
# Test 2: daemon mode joins them the same way
# Test 3: daemon + --keep-alive too (a different branch of the same path)
# -----------------------------------------------------------------------------

set -euo pipefail

FAILED=0

source ../common--source.sh

# The last line of a dryrun is the command the container would run. Quoted by
# the printer, so a joined command shows as one argument and a split one does
# not — which is the whole difference under test.
booth_command_line() { # booth_command_line ARGS... : the `bash -lc ...` line
  run_coding_booth --dryrun --variant base "$@" -- sleep 600 2>&1 | tail -1 | sed 's/^ *//'
}

check() { # check <num> <description> <actual>
  local num="$1" desc="$2" actual="$3"
  local expect="bash -lc 'sleep 600'"
  if diff -u <(echo "$expect" | normalize_output) <(echo "$actual" | normalize_output); then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc"
    echo "  Expected: $expect"
    echo "  Actual:   $actual"
    FAILED=$((FAILED + 1))
  fi
}

check 1 "command mode hands bash -lc one string"             "$(booth_command_line)"
check 2 "daemon mode hands bash -lc one string"              "$(booth_command_line --daemon)"
check 3 "daemon --keep-alive hands bash -lc one string"      "$(booth_command_line --daemon --keep-alive)"

exit $FAILED
