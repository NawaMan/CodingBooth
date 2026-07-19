#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --port NEXT / RANDOM with a :base actually SKIP occupied ports.
#
# The dryrun test (tests/dryrun/test026--port-base.sh) can only prove the base is
# honored, because dryrun deliberately does not bind sockets. This test brings up
# real booths to prove the live scan advances past ports that are already taken.
#
# Test 1: with a booth already on <base>, NEXT:<base> lands on <base>+1000.
# Test 2: with <base> and <base>+1000 both taken, RANDOM:<base> avoids them and
#         returns a free, correctly-aligned host port at or above <base>.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
SUFFIX="$RANDOM-$RANDOM"
NAME_BASE="pns-base-$SUFFIX"
NAME_NEXT="pns-next-$SUFFIX"
NAME_RAND="pns-rand-$SUFFIX"

cleanup() {
  docker rm -f "$NAME_BASE" "$NAME_NEXT" "$NAME_RAND" >/dev/null 2>&1 || true
}
trap cleanup EXIT

is_port_free() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  elif command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"
  else
    ! (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$port" >/dev/null 2>&1)
  fi
}

host_port_10000() {
  docker inspect -f '{{(index (index .HostConfig.PortBindings "10000/tcp") 0).HostPort}}' "$1" 2>/dev/null || true
}

# Find a 1000-aligned base in [40000, 60000] where base, base+1000, and base+2000
# are all free, so the scan has room to advance deterministically.
find_free_base() {
  local b
  for b in $(seq 40000 1000 60000); do
    if is_port_free "$b" && is_port_free "$((b + 1000))" && is_port_free "$((b + 2000))"; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

BASE="$(find_free_base || true)"
if [[ -z "$BASE" ]]; then
  echo "SKIP: could not find a free 1000-aligned base with room above it." >&2
  exit 0
fi

# Occupy <base> with a real booth.
if ! run_coding_booth --variant base --name "$NAME_BASE" --port "$BASE" --daemon --keep-alive -- 'sleep 120' >/dev/null 2>&1; then
  print_test_result "false" "$0" "1" "failed to start the booth occupying base $BASE"
  exit 1
fi

# Test 1: NEXT:<base> must skip the occupied base and pick a free, aligned port
# above it. (We assert "> base and aligned" rather than exactly base+1000, because
# on a shared host base+1000 may itself be taken — in which case NEXT correctly
# advances further, which is still the behavior under test.)
if run_coding_booth --variant base --name "$NAME_NEXT" --port "NEXT:$BASE" --daemon --keep-alive -- 'sleep 120' >/dev/null 2>&1; then
  GOT="$(host_port_10000 "$NAME_NEXT")"
  if [[ -n "$GOT" ]] \
     && [[ "$GOT" -gt "$BASE" ]] \
     && [[ $(( (GOT - BASE) % 1000 )) -eq 0 ]]; then
    print_test_result "true" "$0" "1" "NEXT:$BASE skipped the occupied base and used $GOT"
  else
    print_test_result "false" "$0" "1" "NEXT:$BASE should skip base $BASE and use a higher aligned port, got '${GOT:-<empty>}'"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "NEXT:$BASE run should succeed"
  FAILED=$((FAILED + 1))
fi

# Test 2: base and base+1000 are now both taken; RANDOM:<base> must avoid both and
# return a free, aligned host port at or above base.
if run_coding_booth --variant base --name "$NAME_RAND" --port "RANDOM:$BASE" --daemon --keep-alive -- 'sleep 120' >/dev/null 2>&1; then
  GOT="$(host_port_10000 "$NAME_RAND")"
  if [[ -n "$GOT" ]] \
     && [[ "$GOT" != "$BASE" ]] \
     && [[ "$GOT" != "$((BASE + 1000))" ]] \
     && [[ "$GOT" -ge "$BASE" ]] \
     && [[ $(( (GOT - BASE) % 1000 )) -eq 0 ]]; then
    print_test_result "true" "$0" "2" "RANDOM:$BASE avoided the occupied ports and used $GOT"
  else
    print_test_result "false" "$0" "2" "RANDOM:$BASE returned an invalid/occupied port '${GOT:-<empty>}'"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "RANDOM:$BASE run should succeed"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
