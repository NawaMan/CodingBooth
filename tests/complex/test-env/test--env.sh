#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Smoke test for project-root .env handling and the booth mount
# Verifies:
#   1) a project-root .env is NOT auto-imported (only .booth/.env is)
#   2) data.txt is present and readable inside container
#   3) source data.txt -> PUBLIC variable becomes available

set -euo pipefail

source ../../common--source.sh

# ---- Config -------------------------------------------------------------------
# Path to your booth launcher script. Override via env if needed.
CB_SCRIPT="${CB_SCRIPT:-../../../codingbooth}"
# Canonicalize to absolute path before we cd/pushd anywhere
if command -v readlink >/dev/null 2>&1; then
  CB_SCRIPT="$(readlink -f "$CB_SCRIPT")"
else
  CB_SCRIPT="$(cd "$(dirname "$CB_SCRIPT")" && pwd -P)/$(basename "$CB_SCRIPT")"
fi

# Unique container name to avoid collisions
RUN_ID="$(date +%s)-$$"
CONTAINER_NAME="cb-test-${RUN_ID}"

# ---- Preconditions ------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH"
  exit 1
fi

if [[ ! -x "$CB_SCRIPT" ]]; then
  echo "ERROR: CB_SCRIPT not executable or not found: $CB_SCRIPT" >&2
  exit 1
fi

# ---- Test booth -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
TMPDIR="$(mktemp -d "${SCRIPT_DIR}/.cb-temp.XXXXXX")"
cleanup() {
  # Booth container is started with --rm, so nothing to stop.
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

# Helper to run the booth with our test image and capture stdout
run_cb() {
  # We'll pass an explicit image to avoid any build/pull logic, pick a random port to avoid conflicts
  # Note: The script wraps the command in `bash -lc "<cmd>"` internally
  echo -e "${COLOR_BOOTH:-}> codingbooth -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --name "$CONTAINER_NAME" -- "$@"
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

# 1) A project-root .env is NOT auto-imported.
#
# Only `.booth/.env` is loaded automatically (docs/BOOTH_RUN.md → "Local Secrets"),
# and that file carries a guarantee a bare .env cannot: booth refuses to run unless
# it is gitignored. A project-root .env is commonly committed — sometimes with real
# values by accident — so it is deliberately left alone rather than injected into
# every booth. Opt in explicitly with `env-file = ".env"` in .booth/config.toml.
#
# This asserts the *absence* of that import, so the day someone adds bare-.env
# auto-loading, this test says so instead of the behaviour arriving silently.
out="$(run_cb 'echo "SECRET=[${SECRET:-}]"' | tr -d '\r')"
if [[ "$out" == "SECRET=[]" ]]; then
  pass "project-root .env is not auto-imported"
else
  fail "project-root .env should not be auto-imported, got: '$out'"
fi

# 2) data.txt is present
out="$(run_cb 'cat data.txt' | tr -d '\r')"
if [[ "$out" == "PUBLIC=Yo" ]]; then
  pass "data.txt present in booth mount"
else
  fail "data.txt content mismatch, got: '$out'"
fi

# 3) source data.txt -> PUBLIC available
out="$(run_cb 'source data.txt; echo $PUBLIC' | tr -d '\r')"
if [[ "$out" == "Yo" ]]; then
  pass "Sourcing data.txt exposes PUBLIC"
else
  fail "PUBLIC expected 'Yo' after sourcing, got: '$out'"
fi

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
