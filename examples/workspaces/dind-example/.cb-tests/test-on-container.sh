#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Tests the start/check/stop scripts inside the workspace container.
# Run this script from inside the container.

set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "=== Testing inside container ==="
echo

# Test 1: Start server
echo "Starting server..."
if ! start_out=$(just start 2>&1); then
  echo "$start_out"
  fail "Server failed to start"
fi
pass "Server started"

# Test 2: Check server is running (expects UP)
check_out=""
if just check expect=up > /dev/null 2>&1; then
  pass "Check shows server running"
else
  up=false
  for _ in $(seq 1 15); do
    if check_out=$(just check expect=up 2>&1); then
      up=true
      break
    fi
    sleep 1
  done
  if [[ "$up" == "true" ]]; then
    pass "Check shows server running"
  else
    echo "$check_out"
    fail "Check should show server running"
  fi
fi

# Test 3: Stop server
echo "Stopping server..."
just stop > /dev/null 2>&1
sleep 1
pass "Server stopped"

# Test 4: Check server is not running (expects DOWN)
if just check expect=down > /dev/null 2>&1; then
  pass "Check shows server not running"
else
  fail "Check should show server not running"
fi

echo
echo -e "${GREEN}All container tests passed!${NC}"
