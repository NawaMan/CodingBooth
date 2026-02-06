#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Complex test: --sandboxed with allowlist.txt
# Verifies allowlisted domain is reachable and non-allowlisted is blocked.

set -euo pipefail

source ../../common--source.sh

# ---- Config -------------------------------------------------------------------
CB_SCRIPT="${CB_SCRIPT:-../../../codingbooth}"
if command -v readlink >/dev/null 2>&1; then
  CB_SCRIPT="$(readlink -f "$CB_SCRIPT")"
else
  CB_SCRIPT="$(cd "$(dirname "$CB_SCRIPT")" && pwd -P)/$(basename "$CB_SCRIPT")"
fi

RUN_ID="$(date +%s)-$$"
CONTAINER_NAME="cb-test-sandbox-allowlist-${RUN_ID}"
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
TMPDIR="$(mktemp -d "$HOME/cb-test-sandbox-allowlist.XXXXXX")"
cleanup() {
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

pushd "$TMPDIR" >/dev/null

mkdir -p .booth/sandbox
cat > .booth/sandbox/allowlist.txt <<'EOF'
pypi.org
EOF

run_cb() {
  echo -e "${COLOR_BOOTH:-}> codingbooth --sandboxed --image $IMAGE_NAME --name $CONTAINER_NAME -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --sandboxed --image "$IMAGE_NAME" --name "$CONTAINER_NAME" -- "$@"
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

http_code() {
  run_cb "curl -s -o /dev/null -w \"%{http_code}\" --max-time 8 $1" | tr -d '\r'
}

code="$(http_code "https://pypi.org")"
if [[ "$code" == "000" || "$code" == "403" ]]; then
  fail "allowlisted domain blocked (pypi.org) -> HTTP $code"
else
  pass "allowlisted domain reachable (pypi.org) -> HTTP $code"
fi

code="$(http_code "https://example.com")"
if [[ "$code" == "000" || "$code" == "403" ]]; then
  pass "non-allowlisted domain blocked (example.com) -> HTTP $code"
else
  fail "non-allowlisted domain reachable (example.com) -> HTTP $code"
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
