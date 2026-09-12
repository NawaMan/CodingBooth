#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: shell/exec --code target resolution and its interaction with --name
#
# Covers:
# - --code alone resolves to the running booth on that code path
# - --code alone with --run starts the stopped booth on that code path
# - --code alone with --run creates a new booth rooted at that code path when
#   none exists, and the new booth's cb.code-path label matches it
# - --name + --code together where the named booth's code path matches --code
#   connects normally
# - --name + --code together where they disagree is a hard, unconditional
#   error naming both paths — --accept-existing does NOT bypass it, unlike a
#   --port create-flag mismatch
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME1="connect-code-$RANDOM-$RANDOM"
CODE_A="$(mktemp -d)"
CODE_B="$(mktemp -d)"
CODE_C="$(mktemp -d)"
CREATED_NAME_C=""

cleanup() {
  docker rm -f "$NAME1" >/dev/null 2>&1 || true
  if [[ -n "$CREATED_NAME_C" ]]; then
    docker rm -f "$CREATED_NAME_C" >/dev/null 2>&1 || true
  fi
  rm -rf "$CODE_A" "$CODE_B" "$CODE_C"
}
trap cleanup EXIT

state_of() {
  local s
  s="$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)" || s=""
  s="$(printf '%s' "$s" | tr -d '[:space:]')"
  if [[ -n "$s" ]]; then
    printf '%s\n' "$s"
  else
    printf '%s\n' "missing"
  fi
}

code_path_label() {
  docker inspect -f '{{index .Config.Labels "cb.code-path"}}' "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Setup: a keep-alive booth named NAME1, rooted at CODE_A via --code itself
# (not a `cd`  — run_coding_booth locates the codingbooth binary relative to
# this script's own path, which breaks if the shell's cwd is changed first).
# ---------------------------------------------------------------------------
docker rm -f "$NAME1" >/dev/null 2>&1 || true

set +e
SETUP_OUT="$(run_coding_booth exec --name "$NAME1" --code "$CODE_A" --run --keep-alive -- whoami 2>&1)"
SETUP_EXIT=$?
set -e

if [[ $SETUP_EXIT -eq 0 ]] && [[ "$SETUP_OUT" == *"coder"* ]] && [[ "$(state_of "$NAME1")" == "running" ]]; then
  print_test_result "true" "$0" "1" "setup: booth created and rooted at CODE_A"
else
  print_test_result "false" "$0" "1" "setup should create a running booth on CODE_A"
  echo "  exit=$SETUP_EXIT state=$(state_of "$NAME1")"
  echo "  output: $SETUP_OUT"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 2) --code alone resolves to the running booth on that code path
# ---------------------------------------------------------------------------
set +e
BYCODE_OUT="$(run_coding_booth exec --code "$CODE_A" -- whoami 2>&1)"
BYCODE_EXIT=$?
set -e

if [[ $BYCODE_EXIT -eq 0 ]] && [[ "$BYCODE_OUT" == *"coder"* ]]; then
  print_test_result "true" "$0" "2" "--code alone resolves to the running booth on that code path"
else
  print_test_result "false" "$0" "2" "--code alone should connect to the running booth (exit=$BYCODE_EXIT out=$BYCODE_OUT)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 3) --code alone with --run starts the stopped booth on that code path
# ---------------------------------------------------------------------------
run_coding_booth stop --name "$NAME1" >/dev/null 2>&1 || true
if [[ "$(state_of "$NAME1")" == "running" ]]; then
  print_test_result "false" "$0" "3" "precondition failed: booth should be stopped before this case"
  FAILED=$((FAILED + 1))
fi

set +e
START_OUT="$(run_coding_booth exec --code "$CODE_A" --run --keep-alive -- whoami 2>&1)"
START_EXIT=$?
set -e

if [[ $START_EXIT -eq 0 ]] && [[ "$START_OUT" == *"coder"* ]] && [[ "$(state_of "$NAME1")" == "running" ]]; then
  print_test_result "true" "$0" "3" "--code alone with --run starts the stopped booth on that code path"
else
  print_test_result "false" "$0" "3" "--code --run should start the stopped booth (exit=$START_EXIT state=$(state_of "$NAME1"))"
  echo "  output: $START_OUT"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 4) --code alone with --run creates a new booth rooted at CODE_C when none
#    exists there, and its cb.code-path label matches CODE_C.
# ---------------------------------------------------------------------------
set +e
CREATE_OUT="$(run_coding_booth exec --code "$CODE_C" --run --keep-alive -- whoami 2>&1)"
CREATE_EXIT=$?
set -e

CREATED_NAME_C="$(docker ps -a --filter "label=cb.code-path=$CODE_C" --format '{{.Names}}' | head -1)"
CREATED_LABEL="$(code_path_label "${CREATED_NAME_C:-__none__}")"

if [[ $CREATE_EXIT -eq 0 ]] \
  && [[ "$CREATE_OUT" == *"coder"* ]] \
  && [[ -n "$CREATED_NAME_C" ]] \
  && [[ "$CREATED_LABEL" == "$CODE_C" ]]; then
  print_test_result "true" "$0" "4" "--code --run creates a new booth rooted at that code path"
else
  print_test_result "false" "$0" "4" "--code --run should create a booth labeled with CODE_C"
  echo "  exit=$CREATE_EXIT name=$CREATED_NAME_C label=$CREATED_LABEL want=$CODE_C"
  echo "  output: $CREATE_OUT"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 5) --name + --code together, matching, connects normally
# ---------------------------------------------------------------------------
set +e
MATCH_OUT="$(run_coding_booth exec --name "$NAME1" --code "$CODE_A" -- whoami 2>&1)"
MATCH_EXIT=$?
set -e

if [[ $MATCH_EXIT -eq 0 ]] && [[ "$MATCH_OUT" == *"coder"* ]]; then
  print_test_result "true" "$0" "5" "--name + matching --code connects normally"
else
  print_test_result "false" "$0" "5" "--name + matching --code should connect (exit=$MATCH_EXIT out=$MATCH_OUT)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 6) --name + --code together, mismatched, is a hard error naming both paths
# ---------------------------------------------------------------------------
set +e
MISMATCH_ERR="$(run_coding_booth exec --name "$NAME1" --code "$CODE_B" -- whoami 2>&1)"
MISMATCH_EXIT=$?
set -e

if [[ $MISMATCH_EXIT -ne 0 ]] \
  && grep -q "was created from code path" <<<"$MISMATCH_ERR" \
  && grep -qF "$CODE_A" <<<"$MISMATCH_ERR" \
  && grep -qF "$CODE_B" <<<"$MISMATCH_ERR"; then
  print_test_result "true" "$0" "6" "--name + mismatched --code refuses, naming both paths"
else
  print_test_result "false" "$0" "6" "--name + mismatched --code should refuse and name both paths"
  echo "  exit=$MISMATCH_EXIT"
  echo "  output: $MISMATCH_ERR"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 7) --accept-existing does NOT bypass a --code mismatch (unlike --port)
# ---------------------------------------------------------------------------
set +e
ACCEPT_ERR="$(run_coding_booth exec --name "$NAME1" --code "$CODE_B" --accept-existing -- whoami 2>&1)"
ACCEPT_EXIT=$?
set -e

if [[ $ACCEPT_EXIT -ne 0 ]] && grep -q "was created from code path" <<<"$ACCEPT_ERR"; then
  print_test_result "true" "$0" "7" "--accept-existing does not bypass a --code mismatch"
else
  print_test_result "false" "$0" "7" "--accept-existing should still refuse a --code mismatch (exit=$ACCEPT_EXIT)"
  echo "  output: $ACCEPT_ERR"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
