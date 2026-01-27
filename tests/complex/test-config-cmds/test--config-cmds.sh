#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: cmds in config.toml
#
# This test verifies that the `cmds` array in config.toml is executed
# when no command is provided via CLI (no `-- <command>`).
#
# Test 1: cmds executes when no CLI command provided
# Test 2: CLI command overrides cmds (not appends)
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: cmds in config.toml ==="

FAILED=0

# Test 1: cmds from config.toml should execute when no CLI command provided
# Note: We need to use a subshell approach since booth without -- runs interactively
ACTUAL=$(run_coding_booth 2>/dev/null | tr -d '\r\n')
EXPECTED="CMDS_EXECUTED"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" "cmds from config.toml executed correctly"
else
  print_test_result "false" "$0" "1" "cmds from config.toml should execute when no CLI command"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: CLI command should override cmds (not append)
ACTUAL=$(run_coding_booth -- echo "CLI_OVERRIDE" 2>/dev/null | tr -d '\r\n')
EXPECTED="CLI_OVERRIDE"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "2" "CLI command overrides cmds correctly"
else
  print_test_result "false" "$0" "2" "CLI command should override cmds"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
