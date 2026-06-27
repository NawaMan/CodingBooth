#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Complex test: .booth/ is always read-only inside the container by default.
# Use --writable-booth to opt out of this protection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common--source.sh"

# ---- Config -------------------------------------------------------------------
CB_SCRIPT="${CB_SCRIPT:-../../../codingbooth}"
if command -v readlink >/dev/null 2>&1; then
  CB_SCRIPT="$(readlink -f "$CB_SCRIPT")"
else
  CB_SCRIPT="$(cd "$(dirname "$CB_SCRIPT")" && pwd -P)/$(basename "$CB_SCRIPT")"
fi

RUN_ID="$(date +%s)-$$"
CONTAINER_NAME="cb-test-egress-ro-${RUN_ID}"
IMAGE_NAME="${CB_IMAGE_NAME:-nawaman/codingbooth:base-latest}"

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
TEST_DIR="$(mktemp -d "${SCRIPT_DIR}/.cb-test-egress-ro.XXXXXX")"
cleanup() {
  rm -rf "$TEST_DIR" || true
}
trap cleanup EXIT

pushd "$TEST_DIR" >/dev/null

# Prepare .booth files
mkdir -p .booth/egress

cat > .booth/config.toml <<'EOF'
# test config
variant = "base"
EOF

cat > .booth/Boothfile <<'EOF'
# test Boothfile (not used because we pass --image)
EOF

cat > .booth/egress/allowlist.txt <<'EOF'
github.com
EOF

touch normal.txt

# Helper to run the booth with egress enabled
run_cb() {
  echo -e "${COLOR_BOOTH:-}> codingbooth --egress --image $IMAGE_NAME --name $CONTAINER_NAME -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --egress --image "$IMAGE_NAME" --name "$CONTAINER_NAME" -- "$@"
}

# Helper to run without egress (default)
run_cb_plain() {
  echo -e "${COLOR_BOOTH:-}> codingbooth --image $IMAGE_NAME --name $CONTAINER_NAME -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --image "$IMAGE_NAME" --name "$CONTAINER_NAME" -- "$@"
}

# Helper to run with --writable-booth
run_cb_writable() {
  echo -e "${COLOR_BOOTH:-}> codingbooth --writable-booth --image $IMAGE_NAME --name $CONTAINER_NAME -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --writable-booth --image "$IMAGE_NAME" --name "$CONTAINER_NAME" -- "$@"
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

expect_fail() {
  local label="$1"
  shift
  set +e
  run_cb "$@" >/dev/null 2>&1
  local status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "$label (expected failure, but exit=0)"
  else
    pass "$label (write blocked as expected)"
  fi
}

expect_success() {
  local label="$1"
  shift
  set +e
  run_cb "$@" >/dev/null 2>&1
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    fail "$label (expected success, exit=$status)"
  else
    pass "$label"
  fi
}

# Same helpers, but against the non-egress run
expect_fail_plain() {
  local label="$1"
  shift
  set +e
  run_cb_plain "$@" >/dev/null 2>&1
  local status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "$label (expected failure, but exit=0)"
  else
    pass "$label (write blocked as expected)"
  fi
}

expect_success_plain() {
  local label="$1"
  shift
  set +e
  run_cb_plain "$@" >/dev/null 2>&1
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    fail "$label (expected success, exit=$status)"
  else
    pass "$label"
  fi
}

# Same helpers, but with --writable-booth
expect_fail_writable() {
  local label="$1"
  shift
  set +e
  run_cb_writable "$@" >/dev/null 2>&1
  local status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "$label (expected failure, but exit=0)"
  else
    pass "$label (write blocked as expected)"
  fi
}

expect_success_writable() {
  local label="$1"
  shift
  set +e
  run_cb_writable "$@" >/dev/null 2>&1
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    fail "$label (expected success, exit=$status)"
  else
    pass "$label"
  fi
}

# .booth should be read-only with --egress
expect_fail "config.toml is read-only (egress)" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/config.toml"
expect_fail "Boothfile is read-only (egress)" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/Boothfile"
expect_fail "allowlist.txt is read-only (egress)" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/egress/allowlist.txt"

# Control: normal file should still be writable
expect_success "normal.txt is writable" "bash" "-lc" "echo 'ok' > /home/coder/code/normal.txt"

# .booth should ALSO be read-only without --egress (always-on protection)
expect_fail_plain "config.toml is read-only (no egress)" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/config.toml"
expect_fail_plain "Boothfile is read-only (no egress)" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/Boothfile"
expect_fail_plain "allowlist.txt is read-only (no egress)" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/egress/allowlist.txt"

# Control: normal file should still be writable without egress
expect_success_plain "normal.txt is writable (no egress)" "bash" "-lc" "echo 'ok' > /home/coder/code/normal.txt"

# --writable-booth should allow writing to .booth files
expect_success_writable "config.toml writable with --writable-booth" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/config.toml"
expect_success_writable "Boothfile writable with --writable-booth" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/Boothfile"
expect_success_writable "allowlist.txt writable with --writable-booth" "bash" "-lc" "echo 'thing' > /home/coder/code/.booth/egress/allowlist.txt"

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
