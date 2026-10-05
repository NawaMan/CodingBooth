#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile n8n installation
#
# n8n --version proves the npm package landed. start-n8n must answer
# /healthz, and import:workflow must store a workflow the editor can list.
# The SQLite database must be ~/.n8n/database.sqlite (the path +persist
# mounts), and a Code node must run in both the JavaScript and the Python task
# runner. Python needs the runner venv that n8n--setup.sh builds; npm does not
# ship it.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile n8n Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- n8n --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -q "2.41.5"; then
    print_test_result "true" "$0" "1" "n8n 2.41.5 is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "n8n 2.41.5 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Same container for the whole script: start, wait for /healthz, stop, import.
# One argv after --. A separate `bash -c` is re-parsed as `bash -c` plus only
# the next word, so the rest of the script never becomes the -c program.
# Keep ACTUAL when the booth exits non-zero: import can fail after /healthz.
RUN_SCRIPT='
start-n8n >/tmp/n8n.log 2>&1 &
ok=0
i=0
while [ "$i" -lt 40 ]; do
  if curl -fsS http://127.0.0.1:21200/healthz > /tmp/n8n-health.txt 2>/dev/null; then
    ok=1
    break
  fi
  i=$((i + 1))
  sleep 3
done
echo HEALTH_BEGIN
cat /tmp/n8n-health.txt 2>/dev/null || true
echo
echo HEALTH_END
if [ "$ok" != 1 ]; then
  echo START_FAILED
  cat /tmp/n8n.log || true
  exit 0
fi
stop-n8n || true
sleep 2
echo IMPORT_BEGIN
n8n import:workflow --input=/home/coder/code/workflows/forty-two.json || echo IMPORT_FAILED
echo LIST_BEGIN
n8n list:workflow || echo LIST_FAILED
echo LIST_END
echo DATA_BEGIN
ls ~/.n8n/database.sqlite ~/.n8n/.n8n 2>&1 || true
echo DATA_END
echo JS_BEGIN
n8n execute --id=fortyTwoWorkflow01 2>&1 | grep -E "\"answer\"|\"status\"|rror" || echo JS_FAILED
echo JS_END
n8n import:workflow --input=/home/coder/code/workflows/python-forty-two.json || echo PY_IMPORT_FAILED
echo PY_BEGIN
n8n execute --id=pythonFortyTwo01 2>&1 | grep -E "\"py_answer\"|\"status\"|rror" || echo PY_FAILED
echo PY_END
'
ACTUAL=$(run_coding_booth --silence-build -- "$RUN_SCRIPT" 2>&1) || true

# Here-string, not `echo | grep -q`: grep -q exits at the first match and
# pipefail then reports the writer's SIGPIPE instead of the match.
if [[ "$ACTUAL" == *'"status":"ok"'* ]]; then
    print_test_result "true" "$0" "2" "start-n8n answers /healthz"
else
    print_test_result "false" "$0" "2" "start-n8n should answer /healthz with status ok"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ "$ACTUAL" == *"Forty Two"* ]]; then
    print_test_result "true" "$0" "3" "n8n import:workflow stores Forty Two"
else
    print_test_result "false" "$0" "3" "n8n import:workflow should list Forty Two"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

section() { sed -n "/^$1_BEGIN\$/,/^$1_END\$/p" <<< "$ACTUAL"; }

DATA="$(section DATA)"
if [[ "$DATA" == *"/home/coder/.n8n/database.sqlite"* && "$DATA" != *"/.n8n/.n8n:"* \
      && "$DATA" == *"No such file"* ]]; then
    print_test_result "true" "$0" "4" "SQLite lives at ~/.n8n/database.sqlite, not ~/.n8n/.n8n"
else
    print_test_result "false" "$0" "4" "SQLite should be ~/.n8n/database.sqlite with no nested ~/.n8n/.n8n"
    echo "  Actual output: $DATA"
    FAILED=$((FAILED + 1))
fi

JS="$(section JS)"
if [[ "$JS" == *'"answer": 42'* && "$JS" == *'"status": "success"'* ]]; then
    print_test_result "true" "$0" "5" "JavaScript Code node runs in the task runner (answer 42)"
else
    print_test_result "false" "$0" "5" "JavaScript Code node should return answer 42"
    echo "  Actual output: $JS"
    FAILED=$((FAILED + 1))
fi

PY="$(section PY)"
if [[ "$PY" == *'"py_answer": 42'* && "$PY" == *'"status": "success"'* ]]; then
    print_test_result "true" "$0" "6" "Python Code node runs in the internal Python task runner (py_answer 42)"
else
    print_test_result "false" "$0" "6" "Python Code node should return py_answer 42"
    echo "  Actual output: $PY"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
