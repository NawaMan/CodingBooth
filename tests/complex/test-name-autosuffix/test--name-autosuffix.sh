#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the default container name auto-suffixes with the port ON COLLISION.
#
# Running the same project twice used to fail ("container name already exists").
# Now the first booth keeps the stable folder-derived name, and a second concurrent
# booth of the same project auto-falls back to "<project>-<port>". The stable name
# stays with the first booth, so no-arg lifecycle commands still target it.
#
# Test 1: first run (no --name) uses the bare project name.
# Test 2: second run (no --name) in the same dir auto-suffixes to <project>-<port>.
# Test 3: no-arg `booth stop` still targets the first (bare-named) booth.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
PROJECT="test-name-autosuffix" # = sanitized basename of this directory

cleanup() {
  # Remove every booth this test could have created for this project.
  docker ps -aq --filter "label=cb.project=$PROJECT" 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup # start clean in case a previous run left containers behind

host_port_10000() {
  docker inspect -f '{{(index (index .HostConfig.PortBindings "10000/tcp") 0).HostPort}}' "$1" 2>/dev/null || true
}
state_of() { docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true; }

# Test 1: first run uses the bare project name.
if run_coding_booth --variant base --daemon --keep-alive -- 'sleep 120' >/dev/null 2>&1 \
   && [[ "$(state_of "$PROJECT")" == "running" ]]; then
  print_test_result "true" "$0" "1" "first run uses the bare project name '$PROJECT'"
else
  print_test_result "false" "$0" "1" "first run should create container '$PROJECT'"
  exit 1
fi

# Test 2: second run in the same dir auto-suffixes with its port.
if run_coding_booth --variant base --daemon --keep-alive -- 'sleep 120' >/dev/null 2>&1; then
  # The new container is the one labelled for this project whose name is not the bare name.
  SECOND="$(docker ps -a --filter "label=cb.project=$PROJECT" --format '{{.Names}}' 2>/dev/null | grep -v "^${PROJECT}\$" | head -1)"
  SECOND_PORT="$(host_port_10000 "$SECOND")"
  if [[ -n "$SECOND" ]] && [[ "$SECOND" == "${PROJECT}-${SECOND_PORT}" ]]; then
    print_test_result "true" "$0" "2" "second run auto-suffixes to '$SECOND'"
  else
    print_test_result "false" "$0" "2" "second run should be '${PROJECT}-${SECOND_PORT}', got '${SECOND:-<none>}'"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "second run should succeed (not error on collision)"
  FAILED=$((FAILED + 1))
fi

# Test 3: no-arg `booth stop` still targets the bare-named first booth.
if run_coding_booth stop >/dev/null 2>&1; then
  # keep-alive booths return to 'exited' when stopped (they are not removed).
  if [[ "$(state_of "$PROJECT")" == "exited" ]] && [[ "$(state_of "$SECOND")" == "running" ]]; then
    print_test_result "true" "$0" "3" "no-arg stop targets the stable '$PROJECT', leaving '$SECOND' up"
  else
    print_test_result "false" "$0" "3" "no-arg stop should stop '$PROJECT' only (states: $PROJECT=$(state_of "$PROJECT"), $SECOND=$(state_of "$SECOND"))"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "3" "no-arg stop should succeed"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
