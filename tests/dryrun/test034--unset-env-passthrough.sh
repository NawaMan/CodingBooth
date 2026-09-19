#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: bare Docker env passthrough is omitted when the host variable is unset.
#
# Docker accepts "-e NAME" / "--env NAME" as "copy NAME from the host
# environment". Booth should only issue that flag when NAME actually exists on
# the host. Explicit assignments such as "NAME=" still mean "set this in the
# container" and must be preserved.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

UNSET_VAR="CB_TEST_UNSET_RUN_ENV_$$"
EMPTY_VAR="CB_TEST_EMPTY_RUN_ENV_$$"
SET_VAR="CB_TEST_SET_RUN_ENV_$$"
UNSET_EQUALS_VAR="CB_TEST_UNSET_EQUALS_RUN_ENV_$$"
EMPTY_EQUALS_VAR="CB_TEST_EMPTY_EQUALS_RUN_ENV_$$"

unset "$UNSET_VAR" "$UNSET_EQUALS_VAR"
printf -v "$EMPTY_VAR" '%s' ""
printf -v "$SET_VAR" '%s' "value"
printf -v "$EMPTY_EQUALS_VAR" '%s' ""
export "$EMPTY_VAR" "$SET_VAR" "$EMPTY_EQUALS_VAR"

CONFIG="test--unset-env-passthrough.toml"
trap 'rm -f "$CONFIG"' EXIT

cat > "$CONFIG" <<EOF
variant = "base"
run-args = [
  "-e", "$UNSET_VAR",
  "-e", "$EMPTY_VAR",
  "--env", "$SET_VAR",
  "-e", "CB_TEST_EXPLICIT_EMPTY=",
  "--env", "CB_TEST_EXPLICIT_VALUE=1",
  "--env=$UNSET_EQUALS_VAR",
  "--env=$EMPTY_EQUALS_VAR",
  "--env=CB_TEST_EXPLICIT_EQUALS=1",
]
EOF

ACTUAL=$(run_coding_booth --config "$CONFIG" --dryrun -- echo test 2>&1 | strip_ansi)

FAILED=0

if ! echo "$ACTUAL" | grep -qF -- "$UNSET_VAR"; then
  print_test_result "true" "$0" "1" "unset bare -e variable is omitted"
else
  print_test_result "false" "$0" "1" "unset bare -e variable should be omitted"
  echo "$ACTUAL" | grep -F -- "$UNSET_VAR" || true
  FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -qF -- "-e $EMPTY_VAR"; then
  print_test_result "true" "$0" "2" "empty-but-set bare -e variable is passed through"
else
  print_test_result "false" "$0" "2" "empty-but-set bare -e variable should be passed through"
  echo "$ACTUAL" | grep -F -- "$EMPTY_VAR" || true
  FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -qF -- "--env $SET_VAR"; then
  print_test_result "true" "$0" "3" "set bare --env variable is passed through"
else
  print_test_result "false" "$0" "3" "set bare --env variable should be passed through"
  echo "$ACTUAL" | grep -F -- "$SET_VAR" || true
  FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -qF -- "-e 'CB_TEST_EXPLICIT_EMPTY='"; then
  print_test_result "true" "$0" "4" "explicit empty assignment is preserved"
else
  print_test_result "false" "$0" "4" "explicit empty assignment should be preserved"
  echo "$ACTUAL" | grep -F -- "CB_TEST_EXPLICIT_EMPTY" || true
  FAILED=$((FAILED + 1))
fi

if ! echo "$ACTUAL" | grep -qF -- "$UNSET_EQUALS_VAR"; then
  print_test_result "true" "$0" "5" "unset bare --env= variable is omitted"
else
  print_test_result "false" "$0" "5" "unset bare --env= variable should be omitted"
  echo "$ACTUAL" | grep -F -- "$UNSET_EQUALS_VAR" || true
  FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -qF -- "--env=$EMPTY_EQUALS_VAR"; then
  print_test_result "true" "$0" "6" "empty-but-set bare --env= variable is passed through"
else
  print_test_result "false" "$0" "6" "empty-but-set bare --env= variable should be passed through"
  echo "$ACTUAL" | grep -F -- "$EMPTY_EQUALS_VAR" || true
  FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -qF -- "--env=CB_TEST_EXPLICIT_EQUALS=1"; then
  print_test_result "true" "$0" "7" "explicit --env= assignment is preserved"
else
  print_test_result "false" "$0" "7" "explicit --env= assignment should be preserved"
  echo "$ACTUAL" | grep -F -- "CB_TEST_EXPLICIT_EQUALS" || true
  FAILED=$((FAILED + 1))
fi

exit $FAILED
