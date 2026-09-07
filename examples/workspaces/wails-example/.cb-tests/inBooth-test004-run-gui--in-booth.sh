#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# just run must not SIGTRAP. WebKitGTK 6.0's bubblewrap sandbox cannot create
# user namespaces in a booth; without WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS
# the app dies at start with "Failed to fully launch dbus-proxy".

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== WebKitGTK sandbox is disabled ==="

FAILED=0

if [[ "${WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS:-}" == "1" ]]; then
    echo "  ✅ WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1"
else
    echo "  ❌ WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS is '${WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS:-unset}'"
    FAILED=1
fi

if [[ -z "${DISPLAY:-}" ]]; then
    echo "  ⚠️  DISPLAY is unset — skipping the GUI launch (this booth has no desktop)"
    exit $FAILED
fi

if [[ ! -x bin/booth-counter ]]; then
    echo "=== building the Linux binary first ==="
    just build
fi

echo ""
echo "=== just run stays up (DISPLAY=${DISPLAY}) ==="
# A healthy GUI blocks. timeout 8 → exit 124 means it was still running.
# A sandbox crash is SIGTRAP (rc 133) or task's "exit status 2" (rc 1).
set +e
timeout 8 just run >/tmp/wails-gui.log 2>&1
RC=$?
set -e

if [[ $RC -eq 124 ]]; then
    echo "  ✅ the app was still running after 8s (did not SIGTRAP on launch)"
elif grep -qE 'Failed to fully launch dbus-proxy|No permissions to create new namespace' /tmp/wails-gui.log; then
    echo "  ❌ WebKitGTK sandbox still crashing the app (rc $RC)"
    sed 's/^/      /' /tmp/wails-gui.log | tail -n 20
    FAILED=1
else
    echo "  ❌ just run exited $RC before the timeout (expected 124 = still running)"
    sed 's/^/      /' /tmp/wails-gui.log | tail -n 30
    FAILED=1
fi

exit $FAILED
