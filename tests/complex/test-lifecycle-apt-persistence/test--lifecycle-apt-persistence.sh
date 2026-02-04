#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: lifecycle package persistence (apt-get)
#
# Flow:
# 1) run keep-alive booth (daemon)
# 2) install package #1 with apt-get as root
# 3) stop -> start and verify package #1 still exists
# 4) install package #2, stop
# 5) start and verify package #1 and #2 both exist
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="lifecycle-apt-$RANDOM-$RANDOM"
PKG1="jq"
PKG2="tree"

cleanup() {
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

container_state() {
  docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true
}

# 1) Start keep-alive container in daemon mode.
if run_coding_booth --variant base --name "$NAME" --daemon --keep-alive -- 'sleep 600' >/dev/null 2>&1; then
  print_test_result "true" "$0" "1" "daemon keep-alive booth started for apt persistence test"
else
  print_test_result "false" "$0" "1" "failed to start daemon keep-alive booth"
  FAILED=$((FAILED + 1))
fi

# 2) Install first package via apt-get as root.
if docker exec -u 0 "$NAME" bash -lc "command -v apt-get >/dev/null && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y $PKG1" >/dev/null 2>&1; then
  if docker exec "$NAME" bash -lc "command -v $PKG1 >/dev/null" >/dev/null 2>&1; then
    print_test_result "true" "$0" "2" "installed first package ($PKG1) successfully"
  else
    print_test_result "false" "$0" "2" "first package command not found after install"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "apt-get install for first package should succeed"
  FAILED=$((FAILED + 1))
fi

# 3) Stop/start and verify first package still exists.
if run_coding_booth stop --name "$NAME" >/dev/null 2>&1 \
  && [[ "$(container_state "$NAME")" == "exited" ]] \
  && run_coding_booth start --name "$NAME" --daemon >/dev/null 2>&1 \
  && docker exec "$NAME" bash -lc "command -v $PKG1 >/dev/null" >/dev/null 2>&1; then
  print_test_result "true" "$0" "3" "first package persists across stop/start"
else
  print_test_result "false" "$0" "3" "first package should persist after stop/start"
  FAILED=$((FAILED + 1))
fi

# 4) Install second package, then stop.
if docker exec -u 0 "$NAME" bash -lc "DEBIAN_FRONTEND=noninteractive apt-get install -y $PKG2" >/dev/null 2>&1 \
  && docker exec "$NAME" bash -lc "command -v $PKG2 >/dev/null" >/dev/null 2>&1 \
  && run_coding_booth stop --name "$NAME" >/dev/null 2>&1; then
  print_test_result "true" "$0" "4" "second package installed and container stopped"
else
  print_test_result "false" "$0" "4" "second package install+stop should succeed"
  FAILED=$((FAILED + 1))
fi

# 5) Start and verify both packages exist.
if run_coding_booth start --name "$NAME" --daemon >/dev/null 2>&1 \
  && docker exec "$NAME" bash -lc "command -v $PKG1 >/dev/null && command -v $PKG2 >/dev/null" >/dev/null 2>&1; then
  print_test_result "true" "$0" "5" "both installed packages persist across second start"
else
  print_test_result "false" "$0" "5" "both packages should persist across second start"
  FAILED=$((FAILED + 1))
fi

# 6) cleanup validation
if run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 && ! docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "true" "$0" "6" "cleanup removed lifecycle apt test container"
else
  print_test_result "false" "$0" "6" "cleanup should remove apt test container"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
