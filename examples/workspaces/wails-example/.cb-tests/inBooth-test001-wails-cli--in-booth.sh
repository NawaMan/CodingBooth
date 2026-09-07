#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# The Wails CLI is present and the Linux compile stack is visible — from a
# NON-LOGIN shell. `booth -- ./script.sh` never sources /etc/profile.d, so a
# CLI that only landed in GOPATH/bin would pass interactively and fail here.

set -euo pipefail

echo "=== wails3 on a non-login shell ==="

FAILED=0

if command -v wails3 >/dev/null 2>&1; then
    echo "  ✅ wails3 -> $(command -v wails3)"
else
    echo "  ❌ wails3 NOT on PATH"
    FAILED=1
fi

echo ""
echo "=== wails3 version ==="
VERSION_OUT="$(wails3 version 2>&1 || true)"
if echo "$VERSION_OUT" | grep -qiE 'v?3\.'; then
    echo "  ✅ $VERSION_OUT"
else
    echo "  ❌ wails3 version did not report v3"
    echo "$VERSION_OUT" | sed 's/^/      /'
    FAILED=1
fi

echo ""
echo "=== wails3 doctor sees the GTK4 / WebKitGTK 6.0 stack ==="
# doctor may still warn about optional extras (NSIS). The assertion is that
# the packages this setup installed are found, not that the report is clean.
DOCTOR_OUT="$(wails3 doctor 2>&1 || true)"
if echo "$DOCTOR_OUT" | grep -qiE 'gtk.?4|webkitgtk-?6'; then
    echo "  ✅ doctor mentioned GTK4 / WebKitGTK 6"
else
    echo "  ❌ doctor did not mention GTK4 / WebKitGTK 6"
    echo "$DOCTOR_OUT" | sed 's/^/      /' | head -n 40
    FAILED=1
fi

for tool in go npm gcc pkg-config; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  ✅ $tool -> $(command -v "$tool")"
    else
        echo "  ❌ $tool NOT on PATH (wails3 build needs it)"
        FAILED=1
    fi
done

if pkg-config --exists gtk4 && pkg-config --exists webkitgtk-6.0; then
    echo "  ✅ pkg-config gtk4=$(pkg-config --modversion gtk4) webkitgtk-6.0=$(pkg-config --modversion webkitgtk-6.0)"
else
    echo "  ❌ pkg-config cannot see gtk4 and/or webkitgtk-6.0"
    FAILED=1
fi

exit $FAILED
