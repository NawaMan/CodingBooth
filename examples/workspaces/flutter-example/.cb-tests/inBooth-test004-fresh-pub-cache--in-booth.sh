#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# The recipes still work in a booth whose ~/.pub-cache is empty — the state of
# every run after the first.
#
# booth_counter/ is the mounted project, so .dart_tool/package_config.json
# outlives the booth that wrote it; ~/.pub-cache is in the booth's home, which
# starts fresh. flutter only re-resolves when pubspec.lock is newer than that
# file, so a stale one points at packages that are not there and the build fails
# ("Error when reading '…/.pub-cache/hosted/…'"). Deleting the cache here, after
# test002/003 left a package_config behind, is that second run in one booth.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG=booth_counter/.dart_tool/package_config.json
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"

echo "=== a package_config from an earlier booth, and an empty pub cache ==="

# Precondition: without a package_config that points into the cache, deleting
# the cache proves nothing — this would pass with or without the fix.
if [[ -f "$CONFIG" ]] && grep -q "$PUB_CACHE_DIR" "$CONFIG"; then
    echo "  ✅ $CONFIG points into $PUB_CACHE_DIR"
else
    echo "  ❌ no $CONFIG pointing into $PUB_CACHE_DIR (did test002 run first?)"
    exit 1
fi

rm -rf "$PUB_CACHE_DIR/hosted"
echo "  ✅ removed $PUB_CACHE_DIR/hosted"

echo ""
echo "=== flutter test with that left-over state ==="

if just test; then
    echo "  ✅ the widget test passed"
else
    echo "  ❌ flutter test failed against a stale package_config"
    exit 1
fi
