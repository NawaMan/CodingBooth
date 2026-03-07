#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Smoke test for .booth/.env support
# Verifies:
#   1) .booth/.env variables are visible inside container
#   2) .env is still loaded when env-file is disabled (env-file = "-")

set -euo pipefail

source ../../common--source.sh

# ---- Config -------------------------------------------------------------------
CB_SCRIPT="${CB_SCRIPT:-../../../codingbooth}"
if command -v readlink >/dev/null 2>&1; then
  CB_SCRIPT="$(readlink -f "$CB_SCRIPT")"
else
  CB_SCRIPT="$(cd "$(dirname "$CB_SCRIPT")" && pwd -P)/$(basename "$CB_SCRIPT")"
fi

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR="$(mktemp -d "${SCRIPT_DIR}/.cb-test-env-local.XXXXXX")"
CONTAINER_NAME="cb-test-env-local-$$-$RANDOM"
cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

# Initialize a git repo so the gitignore check works
git init "$TMPDIR" >/dev/null 2>&1

# Create .booth directory with .env and .gitignore
mkdir -p "$TMPDIR/.booth"

cat > "$TMPDIR/.booth/.gitignore" <<'EOF'
.booth.password
.env
EOF

cat > "$TMPDIR/.booth/.env" <<'EOF'
LOCAL_SECRET=FromEnvLocal
SHARED_VAR=LocalValue
EOF

# Helper to run booth from the temp workspace
run_cb() {
  pushd "$TMPDIR" >/dev/null
  echo -e "${COLOR_BOOTH:-}> codingbooth --name $CONTAINER_NAME -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --name "$CONTAINER_NAME" --version latest "$@"
  popd >/dev/null
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

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$msg"
  else
    fail "$msg (expected '$expected', got '$actual')"
  fi
}

# ---- Test 1: .booth/.env variables are visible ------------------------------
out="$(run_cb -- 'echo $LOCAL_SECRET' 2>/dev/null | tr -d '\r')"
assert_eq "FromEnvLocal" "$out" ".booth/.env variable visible in container"

# ---- Test 2: .booth/.env still works when env-file is disabled --------------
cat > "$TMPDIR/.booth/config.toml" <<'EOF'
env-file = "-"
EOF

out="$(run_cb -- 'echo $LOCAL_SECRET' 2>/dev/null | tr -d '\r')"
assert_eq "FromEnvLocal" "$out" ".booth/.env loaded even when env-file disabled"

# Clean up config for any further tests
rm -f "$TMPDIR/.booth/config.toml"

# ---- Summary ------------------------------------------------------------------
if (( failed_checks == 0 )); then
  echo "All $total_checks checks passed."
  exit 0
else
  echo "$failed_checks out of $total_checks checks failed."
  echo "Failed checks:"
  for msg in "${failed_msgs[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi
