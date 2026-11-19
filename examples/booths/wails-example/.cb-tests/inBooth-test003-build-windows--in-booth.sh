#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Windows is the cheap Wails cross-compile from Linux: CGO_ENABLED=0, no Docker.
# Producing a PE .exe is the proof that "cross-compile from this booth" works
# without standing up DinD.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== wails3 build GOOS=windows (amd64 + arm64) ==="

FAILED=0

if just build-windows; then
    echo "  ✅ wails3 build GOOS=windows completed"
else
    echo "  ❌ wails3 build GOOS=windows failed"
    exit 1
fi

echo ""
echo "=== Windows PE binaries exist ==="
found=0
while IFS= read -r exe; do
    found=1
    if [[ ! -s "$exe" ]]; then
        echo "  ❌ empty: $exe"
        FAILED=1
        continue
    fi
    # MZ = DOS/PE magic. `file` is nicer when present, but the magic is enough.
    magic="$(head -c 2 "$exe" | tr -d '\0')"
    if [[ "$magic" == "MZ" ]]; then
        echo "  ✅ $exe ($(wc -c < "$exe") bytes, PE)"
    else
        echo "  ❌ $exe is not a PE executable (no MZ header)"
        FAILED=1
    fi
done < <(find bin build/bin -name '*.exe' 2>/dev/null || true)

if [[ $found -eq 0 ]]; then
    echo "  ❌ no .exe under bin/ or build/bin"
    ls -la bin build/bin 2>/dev/null || true
    FAILED=1
fi

exit $FAILED
