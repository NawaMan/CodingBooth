#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Complex test: egress-allowlist adds extra domains to allowlist file

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
CONTAINER_NAME="cb-test-egress-allowlist-extra-${RUN_ID}"
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
TEST_DIR="$(mktemp -d "${SCRIPT_DIR}/.cb-test-egress-allowlist-extra.XXXXXX")"
cleanup() {
  rm -rf "$TEST_DIR" || true
}
trap cleanup EXIT

pushd "$TEST_DIR" >/dev/null

mkdir -p .booth/egress
cat > .booth/egress/allowlist.txt <<'EOF'
pypi.org
EOF

cat > .booth/config.toml <<'EOF'
egress = true
egress-allowlist-file = ".booth/egress/allowlist.txt"
egress-allowlist = [
  "example.com"
]
EOF

rm -f cb-log.log
touch cb-log.log

run_cb() {
  echo -e "${COLOR_BOOTH:-}> codingbooth --egress --verbose --config .booth/config.toml --image $IMAGE_NAME --name $CONTAINER_NAME -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --egress --verbose --config .booth/config.toml --image "$IMAGE_NAME" --name "$CONTAINER_NAME" -- "$@" | tee cb-log.log
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

proxy_connect_code() {
  local output code
  set +e
  output="$(run_cb "curl -s -o /dev/null -w \"\\n%{http_connect}\\n\" --max-time 8 $1 || true" | tr -d '\r')"
  set -e
  code="$(printf "%s\n" "$output" | awk 'NF{line=$0} END{print line}' | grep -Eo '[0-9]{3}' | tail -n 1 || true)"
  if [[ -z "$code" ]]; then
    code="000"
  fi
  echo "$code"
}

code="$(proxy_connect_code "https://pypi.org")"
if [[ "$code" == "403" ]]; then
  fail "allowlist file domain blocked by proxy (pypi.org) -> CONNECT $code"
else
  pass "allowlist file domain allowed by proxy (pypi.org) -> CONNECT $code"
fi

code="$(proxy_connect_code "https://example.com")"
if [[ "$code" == "403" ]]; then
  fail "egress-allowlist domain blocked by proxy (example.com) -> CONNECT $code"
else
  pass "egress-allowlist domain allowed by proxy (example.com) -> CONNECT $code"
fi

code="$(proxy_connect_code "https://reddit.com")"
if [[ "$code" == "403" ]]; then
  pass "non-allowlisted domain blocked by proxy (reddit.com) -> CONNECT $code"
else
  fail "non-allowlisted domain not blocked by proxy (reddit.com) -> CONNECT $code"
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
