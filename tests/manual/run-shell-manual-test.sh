#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Manual Test: booth shell
# Starts a booth in daemon mode, opens an interactive shell, then cleans up.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTH_BIN="${PROJECT_ROOT}/codingbooth"

NAME="shell-test-$$"

echo "═══════════════════════════════════════════════════════════"
echo "  booth shell — Manual Test"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Step 1: Starting a booth in daemon mode..."
echo "  Container: ${NAME}"
echo ""

"$BOOTH_BIN" --variant base --name "$NAME" --port RANDOM --daemon -- 'sleep 300'

echo ""
echo "  Waiting for container to be fully ready..."
for i in {1..30}; do
    if docker exec "$NAME" id coder >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! docker exec "$NAME" id coder >/dev/null 2>&1; then
    echo "  ERROR: Container not ready after 30s"
    "$BOOTH_BIN" stop "$NAME" 2>/dev/null || true
    exit 1
fi
echo "  Ready."

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Step 2: Opening an interactive shell via 'booth shell'"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  You will be dropped into a bash session inside the container."
echo ""
echo "  Try these:"
echo "    whoami          → expect: coder"
echo "    pwd             → expect: /home/coder/code"
echo "    sudo whoami     → expect: root"
echo "    echo \$SHELL     → expect: /bin/bash"
echo ""
echo "  Type 'exit' or Ctrl+D to leave."
echo ""
echo "───────────────────────────────────────────────────────────"

"$BOOTH_BIN" shell "$NAME"

echo "───────────────────────────────────────────────────────────"
echo ""
echo "  Were you able to use the shell inside the booth? (y/n)"
read -r answer
echo ""

echo "Step 3: Cleaning up..."
"$BOOTH_BIN" stop "$NAME" 2>/dev/null || true

echo ""
if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    echo "═══════════════════════════════════════════════════════════"
    echo "  ✅ Test PASSED"
    echo "═══════════════════════════════════════════════════════════"
else
    echo "═══════════════════════════════════════════════════════════"
    echo "  ❌ Test FAILED"
    echo "═══════════════════════════════════════════════════════════"
    exit 1
fi
