#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

LOG="$0.log"
NAME="log-time-test-$RANDOM"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Test 1: Without --log-time, daemon output should NOT have timestamps
run_coding_booth --variant base --name "$NAME" --daemon -- 'sleep 5' > "$LOG" 2>&1
cleanup

if grep -qE '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$LOG"; then
  print_test_result "false" "$0" "1" "Without --log-time, output should not contain timestamps"
  exit 1
else
  print_test_result "true" "$0" "1" "Without --log-time, output has no timestamps"
fi

# Test 2: With --log-time, daemon output should have timestamps
run_coding_booth --variant base --name "$NAME" --log-time --daemon -- 'sleep 5' > "$LOG" 2>&1
cleanup

if grep -qE '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$LOG"; then
  print_test_result "true" "$0" "2" "With --log-time, output contains timestamps"
else
  print_test_result "false" "$0" "2" "With --log-time, output should contain timestamps"
  echo "  Output:"
  head -5 "$LOG" | sed 's/^/    /'
  exit 1
fi
