#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a fixed port that is already taken stops the booth before docker run.
#
# A NEXT/RANDOM booth port moves out of the way; a fixed one (--port N, or a
# published -p N:M) does not. Without the check in CheckHostPortsFree, a busy
# fixed port reached `docker run`, which failed with "port is already
# allocated" and named neither the mapping nor a fix. The unit tests cover the
# decision; this covers that `booth run` really makes it, before any
# container exists, and that a free fixed port still starts.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

if ! have_python3; then
  echo "SKIP: needs python3 to hold a port"
  exit 0
fi

NAME="fixed-port-$RANDOM"
LOG="$0.log"
HELD="$(pick_free_port)"
FREE="$(pick_free_port_other_than "$HELD")"
HOLDER_PID=""

cleanup() {
  [[ -n "$HOLDER_PID" ]] && kill "$HOLDER_PID" >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -f "${READY:-}"
}
trap cleanup EXIT

# Hold HELD on loopback — the address the booth publishes on — for the test's length.
# The holder writes READY once it listens; probing the port instead would race it.
READY="$(mktemp -u)"
python3 -c '
import socket, sys, time
s = socket.socket()
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen()
open(sys.argv[2], "w").close()
time.sleep(600)
' "$HELD" "$READY" &
HOLDER_PID=$!

for i in {1..50}; do
  if [[ -e "$READY" ]]; then
    break
  fi
  sleep 0.1
done
if [[ ! -e "$READY" ]]; then
  print_test_result "false" "$0" "0" "Could not hold port $HELD for the test"
  exit 1
fi

: > "$LOG"

# -------------------------------------------------------
# 1. A fixed booth port that is taken is refused, by name, with the fix.
# -------------------------------------------------------
OUT=$(run_coding_booth --name "$NAME" --port "$HELD" -- echo started 2>&1)
RC=$?
echo "$OUT" >> "$LOG"

if [[ $RC -ne 0 ]] \
   && grep -q "booth port $HELD is already in use" <<< "$OUT" \
   && grep -q -- "--port NEXT" <<< "$OUT" \
   && ! grep -q "port is already allocated" <<< "$OUT"; then
  print_test_result "true" "$0" "1" "A taken fixed booth port is refused before docker run, suggesting --port NEXT"
else
  print_test_result "false" "$0" "1" "A taken fixed booth port should be refused with a named error (rc=$RC): $OUT"
  exit 1
fi

# -------------------------------------------------------
# 2. A fixed published port that is taken is refused, naming the mapping.
# -------------------------------------------------------
OUT=$(run_coding_booth --name "$NAME" --port "$FREE" -p "$HELD:80" -- echo started 2>&1)
RC=$?
echo "$OUT" >> "$LOG"

if [[ $RC -ne 0 ]] \
   && grep -q "host port $HELD is already in use — \"$HELD:80\"" <<< "$OUT" \
   && grep -q "+OFFSET" <<< "$OUT"; then
  print_test_result "true" "$0" "2" "A taken fixed published port is refused, naming the mapping and suggesting +OFFSET"
else
  print_test_result "false" "$0" "2" "A taken fixed published port should be refused naming \"$HELD:80\" (rc=$RC): $OUT"
  exit 1
fi

# -------------------------------------------------------
# 3. Neither refusal left a container behind.
# -------------------------------------------------------
if ! docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "true" "$0" "3" "A refused booth leaves no container"
else
  print_test_result "false" "$0" "3" "A refused booth should leave no container, but $NAME exists"
  exit 1
fi

# -------------------------------------------------------
# 4. A fixed booth port that is free still starts.
# -------------------------------------------------------
OUT=$(run_coding_booth --name "$NAME" --port "$FREE" -- echo started 2>&1)
RC=$?
echo "$OUT" >> "$LOG"

if [[ $RC -eq 0 ]] && grep -q "^started" <<< "$OUT"; then
  print_test_result "true" "$0" "4" "A free fixed booth port starts as before"
else
  print_test_result "false" "$0" "4" "A free fixed booth port should start (rc=$RC): $OUT"
  exit 1
fi
