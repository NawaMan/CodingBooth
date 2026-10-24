#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile ThinkRail Installation
#
# Verifies that `setup thinkrail` installs the ThinkRail CLI AND that it serves
# its web UI: start-thinkrail (the desktop-icon starter, bound to 0.0.0.0) is
# run in the background and the app page is fetched with curl. Signing in to a
# model provider needs credentials, so the agent itself is not driven here.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile ThinkRail Installation ==="

FAILED=0

# Test 1: thinkrail is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- thinkrail --version 2>/dev/null | tail -1)

if echo "$ACTUAL" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "thinkrail is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "thinkrail should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: start-thinkrail serves the ThinkRail web app on all interfaces
ACTUAL=$(run_coding_booth --silence-build -- \
  "start-thinkrail > /tmp/thinkrail.log 2>&1 &
   IP=\$(hostname -I | awk '{print \$1}')
   for i in \$(seq 1 30); do curl -sf -o /dev/null http://\$IP:24242/ && break; sleep 1; done
   curl -s http://\$IP:24242/ | grep -o '<title>[^<]*</title>'" \
  2>/dev/null | tail -1)

if [[ "$ACTUAL" == "<title>ThinkRail</title>" ]]; then
    print_test_result "true" "$0" "2" "thinkrail serves its web UI beyond loopback"
else
    print_test_result "false" "$0" "2" "thinkrail should serve its web UI beyond loopback"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
