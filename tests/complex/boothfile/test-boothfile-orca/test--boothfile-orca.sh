#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Orca Installation
#
# Verifies that `setup orca` installs Orca AND that its headless runtime works
# on the base variant (no desktop): orca-serve starts the server, its own PTY
# self-test passes (it can spawn terminals for agents), the web client is
# served, and orca-pairing hands back a link that points at the advertised
# host port. orca-pairing is called right after the server starts, so it has to
# wait for the link rather than report there is none. The desktop app is exercised by hand on desktop-xfce.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Orca Installation ==="

FAILED=0

# One booth run: start the server, wait for it, then report each check on its own line.
ACTUAL=$(run_coding_booth --silence-build -- \
  "ORCA_HOST_PORT=26768 orca-serve > /tmp/orca-serve.log 2>&1 &
   sleep 1
   orca-pairing | grep -q '^Web client URL: http://localhost:26768/web-index.html#pairing=' && echo LINK=yes
   for i in \$(seq 1 60); do grep -q '^Orca server ready' /tmp/orca-serve.log && break; sleep 1; done
   for i in \$(seq 1 30); do curl -sf -o /dev/null http://127.0.0.1:6768/web-index.html && break; sleep 1; done
   grep -q '^Orca server ready' /tmp/orca-serve.log && echo READY=yes
   grep -q 'PTY self-test passed' /tmp/orca-serve.log && echo PTY=yes
   echo WEB=\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6768/web-index.html)" \
  2>/dev/null)

check() { # <n> <pattern> <message>
    if echo "$ACTUAL" | grep -qx "$2"; then
        print_test_result "true" "$0" "$1" "$3"
    else
        print_test_result "false" "$0" "$1" "$3"
        FAILED=$((FAILED + 1))
    fi
}
check 1 'READY=yes' "orca-serve starts a headless Orca runtime"
check 2 'PTY=yes'   "the runtime passes its terminal (PTY) self-test"
check 3 'WEB=200'   "the runtime serves the Orca web client"
check 4 'LINK=yes'  "orca-pairing waits for a link to the advertised host port"
[[ $FAILED -eq 0 ]] || echo "  Actual output: ${ACTUAL:-<empty>}"

exit $FAILED
