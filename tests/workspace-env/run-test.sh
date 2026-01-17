#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Smoke test for env-file passthrough and workspace mount
# Verifies:
#   1) .env -> SECRET is visible inside container
#   2) data.txt is present and readable inside container
#   3) source data.txt -> PUBLIC variable becomes available

set -euo pipefail

source ../common--source.sh

# ---- Config -------------------------------------------------------------------
# Path to your workspace launcher script. Override via env if needed.
CB_SCRIPT="${CB_SCRIPT:-../../workspace}"
# Canonicalize to absolute path before we cd/pushd anywhere
if command -v readlink >/dev/null 2>&1; then
  CB_SCRIPT="$(readlink -f "$CB_SCRIPT")"
else
  CB_SCRIPT="$(cd "$(dirname "$CB_SCRIPT")" && pwd -P)/$(basename "$CB_SCRIPT")"
fi

# Unique container name to avoid collisions
RUN_ID="$(date +%s)-$$"
CONTAINER_NAME="ws-test-${RUN_ID}"

# ---- Preconditions ------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH"
  exit 1
fi

if [[ ! -x "$CB_SCRIPT" ]]; then
  echo "ERROR: CB_SCRIPT not executable or not found: $CB_SCRIPT" >&2
  exit 1
fi

# ---- Test workspace -----------------------------------------------------------
TMPDIR="$(mktemp -d "$HOME/ws-test.XXXXXX")"
cleanup() {
  # Workspace container is started with --rm, so nothing to stop.
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

pushd "$TMPDIR" >/dev/null

# Create files as per your example
cat > .env <<'EOF'
SECRET=Boo
EOF

cat > data.txt <<'EOF'
PUBLIC=Yo
EOF

# Helper to run the workspace with our test image and capture stdout
run_ws() {
  # We’ll pass an explicit image to avoid any build/pull logic, pick a random port to avoid conflicts
  # Note: The script wraps the command in `bash -lc "<cmd>"` internally
  "$CB_SCRIPT" -- "$@"
}

# ---- Assertions ---------------------------------------------------------------
total_checks=0
failed_checks=0
failed_msgs=()

pass() {
  total_checks=$((total_checks + 1))
  print_test_result "true" "$0" "$total_checks" "$*"
}

fail() {
  total_checks=$((total_checks + 1))
  failed_checks=$((failed_checks + 1))
  failed_msgs+=("$*")
  print_test_result "false" "$0" "$total_checks" "$*"
}

# 1) SECRET from .env is visible
out="$(run_ws 'echo $SECRET' | tr -d '\r')"
[[ "$out" == "Boo" ]] || fail "SECRET expected 'Boo', got: '$out'"
pass "SECRET from .env visible in container"

# 2) data.txt is present
out="$(run_ws 'cat data.txt' | tr -d '\r')"
[[ "$out" == "PUBLIC=Yo" ]] || fail "data.txt content mismatch, got: '$out'"
pass "data.txt present in workspace mount"

# 3) source data.txt -> PUBLIC available
out="$(run_ws 'source data.txt; echo $PUBLIC' | tr -d '\r')"
[[ "$out" == "Yo" ]] || fail "PUBLIC expected 'Yo' after sourcing, got: '$out'"
pass "Sourcing data.txt exposes PUBLIC"

popd >/dev/null

# ---- Summary ------------------------------------------------------------------
if (( failed_checks == 0 )); then
  echo "✅ All $total_checks checks passed."
  exit 0
else
  echo "❌ $failed_checks out of $total_checks checks failed."
  echo "Failed checks:"
  for msg in "${failed_msgs[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi
