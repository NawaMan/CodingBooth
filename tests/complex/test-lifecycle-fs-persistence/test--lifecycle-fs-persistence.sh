#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: lifecycle filesystem persistence across stop/start
#
# Flow:
# 1) run keep-alive booth and write files to /tmp and /home/coder
# 2) start and verify files exist
# 3) write more files, stop
# 4) start again and verify all files exist
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="lifecycle-fs-$RANDOM-$RANDOM"
TMP_FILE_1="/tmp/lifecycle-file-1.txt"
HOME_FILE_1="/home/coder/lifecycle-file-1.txt"
TMP_FILE_2="/tmp/lifecycle-file-2.txt"
HOME_FILE_2="/home/coder/lifecycle-file-2.txt"

cleanup() {
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

container_state() {
  docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true
}

# 1) run keep-alive in daemon mode, write first pair, then stop.
if run_coding_booth --variant base --name "$NAME" --daemon --keep-alive -- 'sleep 600' >/dev/null 2>&1 \
  && docker exec "$NAME" bash -lc "echo first > '$TMP_FILE_1' && echo first > '$HOME_FILE_1'" >/dev/null 2>&1 \
  && run_coding_booth stop --name "$NAME" >/dev/null 2>&1; then
  if [[ "$(container_state "$NAME")" == "exited" ]]; then
    print_test_result "true" "$0" "1" "run+write+stop created first files in stopped container"
  else
    print_test_result "false" "$0" "1" "container should be exited after first stop"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "run+write+stop sequence should succeed"
  FAILED=$((FAILED + 1))
fi

# 2) start and verify first pair exists.
if run_coding_booth start --name "$NAME" --daemon >/dev/null 2>&1; then
  if docker exec "$NAME" bash -lc "test -f '$TMP_FILE_1' && test -f '$HOME_FILE_1'" >/dev/null 2>&1; then
    print_test_result "true" "$0" "2" "first /tmp and /home/coder files persist after first start"
  else
    print_test_result "false" "$0" "2" "expected first files to exist after first start"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "start should succeed"
  FAILED=$((FAILED + 1))
fi

# 3) write second pair while running, then stop.
if docker exec "$NAME" bash -lc "echo second > '$TMP_FILE_2' && echo second > '$HOME_FILE_2'" >/dev/null 2>&1 \
  && run_coding_booth stop --name "$NAME" >/dev/null 2>&1; then
  if [[ "$(container_state "$NAME")" == "exited" ]]; then
    print_test_result "true" "$0" "3" "second files written and container stopped cleanly"
  else
    print_test_result "false" "$0" "3" "container should be exited after stop"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "3" "write+stop sequence should succeed"
  FAILED=$((FAILED + 1))
fi

# 4) start again and verify both file pairs.
if run_coding_booth start --name "$NAME" --daemon >/dev/null 2>&1; then
  if docker exec "$NAME" bash -lc \
    "test -f '$TMP_FILE_1' && test -f '$HOME_FILE_1' && test -f '$TMP_FILE_2' && test -f '$HOME_FILE_2'" >/dev/null 2>&1; then
    print_test_result "true" "$0" "4" "all files persist across second start"
  else
    print_test_result "false" "$0" "4" "expected both file sets after second start"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "4" "second start should succeed"
  FAILED=$((FAILED + 1))
fi

# 5) cleanup validation
if run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 && ! docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "true" "$0" "5" "cleanup removed lifecycle container"
else
  print_test_result "false" "$0" "5" "cleanup should remove container"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
