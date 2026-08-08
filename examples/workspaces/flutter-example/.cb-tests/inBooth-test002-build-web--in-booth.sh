#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Flutter compiles this example's app for the web.
#
# The heaviest assertion in the example and the most meaningful one: it drives
# the Dart compiler, the web engine artifacts the setup precached, and the SDK
# cache being writable, all at once. A booth that passes test001 and fails this
# one installed a Flutter that cannot build anything.

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../booth_counter" && pwd)"
cd "$APP_DIR"

echo "=== flutter build web in $APP_DIR ==="

FAILED=0

# Start clean so a stale build/ from a previous run cannot make this pass.
rm -rf build

if flutter build web --release; then
    echo "  ✅ flutter build web completed"
else
    echo "  ❌ flutter build web failed"
    exit 1
fi

echo ""
echo "=== the compiled bundle exists ==="
for artifact in build/web/main.dart.js build/web/index.html build/web/flutter.js; do
    if [[ -s "$artifact" ]]; then
        echo "  ✅ $artifact ($(wc -c < "$artifact") bytes)"
    else
        echo "  ❌ missing or empty: $artifact"
        FAILED=1
    fi
done

echo ""
echo "=== the app's own code reached the bundle ==="
# Guards against a build that succeeded but compiled a different entrypoint:
# the counter's label is a string this example owns, so it can only be in
# main.dart.js if lib/main.dart is what was compiled.
if grep -q "Booth counter" build/web/main.dart.js; then
    echo "  ✅ the app's UI string is present in main.dart.js"
else
    echo "  ❌ the app's UI string is missing from main.dart.js"
    FAILED=1
fi

exit $FAILED
