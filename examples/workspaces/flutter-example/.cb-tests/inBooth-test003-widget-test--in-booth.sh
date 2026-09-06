#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# `flutter test` runs the app's widget test.
#
# Distinct from test002: that one compiles the app, this one runs the Flutter
# test runner, which drives the framework itself — a headless render, a tap, and
# a rebuild. A booth can compile fine and still have a broken test harness.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== flutter test in $ROOT/booth_counter ==="

if just test; then
    echo "  ✅ the widget test passed"
else
    echo "  ❌ flutter test failed"
    exit 1
fi
