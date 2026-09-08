#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile AnythingLLM starter
#
# 1) setup anythingllm installs start-anythingllm (from a fixture app tree).
# 2) start-anythingllm serves /api/ping — the same health URL the real
#    AnythingLLM docker-healthcheck hits in the first five minutes.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile AnythingLLM starter ==="

FAILED=0

# One booth: prove the starter landed, then that /api/ping answers — the same
# health URL the real AnythingLLM docker-healthcheck hits in the first five minutes.
OUT=$(run_coding_booth --silence-build -- '
  command -v start-anythingllm
  start-anythingllm 3001 >/tmp/anythingllm.log 2>&1 &
  ready=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if curl -fsS -m 2 "http://127.0.0.1:3001/api/ping" >/dev/null 2>&1; then
      ready=yes
      break
    fi
    sleep 1
  done
  if [[ -z "$ready" ]]; then
    echo "PING_FAIL"
    cat /tmp/anythingllm.log >&2 || true
    exit 1
  fi
  curl -fsS -m 2 "http://127.0.0.1:3001/api/ping"
') || true

STARTER_LINE=$(printf '%s\n' "$OUT" | grep -E '/start-anythingllm' | head -1 || true)
if echo "$STARTER_LINE" | grep -q "start-anythingllm"; then
    print_test_result "true"  "$0" "1" "start-anythingllm is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "start-anythingllm should be on PATH"
    echo "  Actual output: $OUT"
    FAILED=$((FAILED + 1))
fi

if echo "$OUT" | grep -q "AnythingLLM"; then
    print_test_result "true"  "$0" "2" "start-anythingllm answers /api/ping"
else
    print_test_result "false" "$0" "2" "AnythingLLM should answer /api/ping"
    echo "  Actual output: $OUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
