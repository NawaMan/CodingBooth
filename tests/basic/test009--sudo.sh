#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: --sudo true allows sudo, --sudo false revokes it
# -------------------------------------------------------

# -------------------------------------------------------
# Test 1: --sudo true (default) — sudo works
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --sudo true -- sudo touch /opt/test-sudo-true 2>&1) || true
EXIT_CODE=$(run_coding_booth --variant base --sudo true -- bash -c 'sudo touch /opt/test-sudo-true && echo OK' 2>&1 | tail -1)

if [[ "$EXIT_CODE" == "OK" ]]; then
  print_test_result "true" "$0" "1" "sudo works with --sudo true"
else
  print_test_result "false" "$0" "1" "sudo works with --sudo true (got: $EXIT_CODE)"
  exit 1
fi

# -------------------------------------------------------
# Test 2: --sudo false — sudo is revoked
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --sudo false -- bash -c 'sudo touch /opt/test-sudo-false 2>&1; echo "EXIT=$?"' 2>&1 | tail -1)

if [[ "$ACTUAL" == "EXIT=1" ]]; then
  print_test_result "true" "$0" "2" "sudo fails with --sudo false"
else
  print_test_result "false" "$0" "2" "sudo fails with --sudo false (got: $ACTUAL)"
  exit 1
fi

# -------------------------------------------------------
# Test 3: --no-sudo shorthand — sudo is revoked
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base --no-sudo -- bash -c 'sudo touch /opt/test-no-sudo 2>&1; echo "EXIT=$?"' 2>&1 | tail -1)

if [[ "$ACTUAL" == "EXIT=1" ]]; then
  print_test_result "true" "$0" "3" "sudo fails with --no-sudo"
else
  print_test_result "false" "$0" "3" "sudo fails with --no-sudo (got: $ACTUAL)"
  exit 1
fi
