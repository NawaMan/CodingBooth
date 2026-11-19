#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# just build produces a real APK of this app. That is the first-five-minutes
# test for wails+android: not sdkmanager --version, a compile.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== just build (debug APK) in $ROOT ==="

FAILED=0

rm -f bin/booth-counter.apk

if just build; then
    echo "  ✅ just build completed"
else
    echo "  ❌ just build failed"
    exit 1
fi

APK=bin/booth-counter.apk
echo ""
echo "=== APK exists ==="
if [[ -s "$APK" ]]; then
    echo "  ✅ $APK ($(wc -c < "$APK") bytes)"
else
    echo "  ❌ missing or empty: $APK"
    ls -la bin 2>/dev/null || true
    exit 1
fi

# APK is a ZIP. PK magic.
magic="$(head -c 2 "$APK" | tr -d '\0')"
if [[ "$magic" == "PK" ]]; then
    echo "  ✅ $APK has a ZIP/APK header"
else
    echo "  ❌ $APK is not a ZIP/APK (no PK header)"
    FAILED=1
fi

echo ""
echo "=== the app's own UI string reached the APK ==="
# The frontend is embedded in lib/<abi>/libwails.so. Gradle may store that .so
# deflated in the APK, and then a grep of the APK itself cannot see the string:
# look inside the .so as well.
in_native_lib() {
    if command -v unzip >/dev/null 2>&1; then
        # grep -c, not -q: -q stops at the first match, unzip then dies of SIGPIPE,
        # and pipefail turns that into a failure.
        unzip -p "$APK" 'lib/*/libwails.so' 2>/dev/null | grep -a -c "Booth counter" >/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$APK" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
sys.exit(0 if any(n.endswith('/libwails.so') and b'Booth counter' in z.read(n) for n in z.namelist()) else 1)
PY
    else
        return 1
    fi
}
if grep -a -q "Booth counter" "$APK" || in_native_lib; then
    echo "  ✅ 'Booth counter' is present in $APK"
else
    echo "  ❌ 'Booth counter' is missing from the APK (frontend not packaged?)"
    FAILED=1
fi

exit $FAILED
