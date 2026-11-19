#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Packages resolved in one booth are still there in the next.
#
# booth_counter/.dart_tool is in the mounted project, so it outlives the booth
# that wrote it; ~/.pub-cache is in the booth's home. Without flutter+pub-cache
# (auto-selected, it bind-mounts ~/.pub-cache from .booth/cache/) the second
# booth starts with an empty cache under a package_config that points into it,
# and flutter -- seeing that file newer than pubspec.lock -- does not resolve
# again: `flutter test` fails reading packages that are gone.
#
# Two one-shot booths, so two containers. The second one deliberately does NOT
# run `flutter pub get` (which `just test` does): that would mask the bug.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"
cd "$SCRIPT_DIR/.."

PORT="${CB_PORT:-50412}"
FAILED=0

echo "=== booth 1: flutter pub get ==="
if "$BOOTH" --port "$PORT" -- 'cd booth_counter && flutter pub get </dev/null' >"$0.out" 2>&1 \
   && [[ -f booth_counter/.dart_tool/package_config.json ]]; then
    echo -e "  ${GREEN}✅ resolved; booth_counter/.dart_tool/package_config.json written${NC}"
else
    echo -e "  ${RED}❌ flutter pub get failed or wrote no package_config — see $0.out${NC}"
    exit 1
fi

echo ""
echo "=== booth 2: flutter test, without pub get ==="
if "$BOOTH" --port "$PORT" -- 'cd booth_counter && flutter test </dev/null' >>"$0.out" 2>&1; then
    echo -e "  ${GREEN}✅ the widget test passed against the previous booth's packages${NC}"
else
    echo -e "  ${RED}❌ flutter test failed in the second booth — is ~/.pub-cache persisted? See $0.out${NC}"
    grep -m3 -E "Error when reading|pub-cache" "$0.out" | sed 's/^/     /' || true
    FAILED=1
fi

exit $FAILED
