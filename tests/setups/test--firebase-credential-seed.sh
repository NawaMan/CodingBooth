#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: firebase credential seed startup (empty / "{}" placeholder)
#
# Extracts the startup script embedded in firebase--setup.sh and asserts it:
#   - copies host seed when dest is missing, empty, or only "{}"
#   - leaves a real login file alone
#   - no-ops when the seed file is absent
# No Docker / image build — hermetic host-side check.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/variants/base/setups/firebase--setup.sh"

if [[ ! -f "$SETUP" ]]; then
  echo "FAIL: setup not found: $SETUP"
  exit 1
fi

# Extract the heredoc body between <<'STARTUP' and the closing STARTUP line.
STARTUP_BODY=$(awk "
  /^cat > \"\\\$\\{STARTUP_FILE\\}\" <<'STARTUP'\$/ { grab=1; next }
  grab && /^STARTUP\$/ { exit }
  grab { print }
" "$SETUP")

if [[ -z "$STARTUP_BODY" ]]; then
  echo "FAIL: could not extract STARTUP body from firebase--setup.sh"
  exit 1
fi

HOST_CREDS='{"tokens":{"refresh_token":"host-token-abc"},"user":{"email":"dev@example.com"}}'
REAL_LOGIN='{"tokens":{"refresh_token":"container-login"},"user":{"email":"in-booth@example.com"}}'

FAILED=0

# dest_mode: missing | empty | content:<text>
# expect: host | keep
run_case() {
  local name="$1"
  local dest_mode="$2"
  local expect="$3"

  local work seed_file home_dir dest_file
  work=$(mktemp -d)
  seed_file="$work/seed/firebase-tools.json"
  home_dir="$work/home"
  dest_file="$home_dir/.config/configstore/firebase-tools.json"

  mkdir -p "$(dirname "$seed_file")"
  printf '%s\n' "$HOST_CREDS" >"$seed_file"

  case "$dest_mode" in
    missing) ;;
    empty)
      mkdir -p "$(dirname "$dest_file")"
      : >"$dest_file"
      ;;
    content:*)
      mkdir -p "$(dirname "$dest_file")"
      printf '%s' "${dest_mode#content:}" >"$dest_file"
      ;;
    *)
      echo "FAIL: $name — bad dest_mode $dest_mode"
      rm -rf "$work"
      FAILED=$((FAILED + 1))
      return
      ;;
  esac

  printf '%s\n' "$STARTUP_BODY" >"$work/startup.sh"
  if ! HOME="$home_dir" CB_FIREBASE_SEED_FILE="$seed_file" bash "$work/startup.sh"; then
    echo "FAIL: $name — startup exited non-zero"
    rm -rf "$work"
    FAILED=$((FAILED + 1))
    return
  fi

  if [[ ! -f "$dest_file" ]]; then
    echo "FAIL: $name — dest missing after startup"
    rm -rf "$work"
    FAILED=$((FAILED + 1))
    return
  fi

  local after
  after=$(cat "$dest_file")

  if [[ "$expect" == host ]]; then
    if [[ "$after" != *host-token-abc* ]]; then
      echo "FAIL: $name — expected host credentials"
      echo "  got: $after"
      FAILED=$((FAILED + 1))
      rm -rf "$work"
      return
    fi
  elif [[ "$expect" == keep ]]; then
    if [[ "$after" == *host-token-abc* ]]; then
      echo "FAIL: $name — should not have overwritten real login"
      FAILED=$((FAILED + 1))
      rm -rf "$work"
      return
    fi
    if [[ "$after" != "$REAL_LOGIN" ]]; then
      echo "FAIL: $name — real login content changed unexpectedly"
      echo "  got: $after"
      FAILED=$((FAILED + 1))
      rm -rf "$work"
      return
    fi
  fi

  echo "OK: $name"
  rm -rf "$work"
}

run_case "missing dest" "missing" "host"
run_case "empty dest" "empty" "host"
run_case "placeholder {}" "content:{}" "host"
run_case "placeholder with whitespace" $'content:  {\n  }\n' "host"
run_case "real login preserved" "content:${REAL_LOGIN}" "keep"

# No seed file → no change / no crash
{
  work=$(mktemp -d)
  home_dir="$work/home"
  dest_file="$home_dir/.config/configstore/firebase-tools.json"
  mkdir -p "$(dirname "$dest_file")"
  printf '%s' "{}" >"$dest_file"
  printf '%s\n' "$STARTUP_BODY" >"$work/startup.sh"
  if ! HOME="$home_dir" CB_FIREBASE_SEED_FILE="$work/missing.json" bash "$work/startup.sh"; then
    echo "FAIL: missing seed — startup exited non-zero"
    FAILED=$((FAILED + 1))
  else
    after=$(cat "$dest_file")
    if [[ "$after" == "{}" ]]; then
      echo "OK: missing seed leaves dest alone"
    else
      echo "FAIL: missing seed should not alter dest"
      FAILED=$((FAILED + 1))
    fi
  fi
  rm -rf "$work"
}

if [[ "$FAILED" -eq 0 ]]; then
  echo "All firebase credential seed unit checks passed."
  exit 0
fi
echo "$FAILED firebase credential seed check(s) failed."
exit 1
