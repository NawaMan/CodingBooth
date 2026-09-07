#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# wails3 build produces a Linux GUI binary, and this example's own UI string
# is in it. That is the first-five-minutes test: not --version, a compile.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== wails3 build (native Linux) in $ROOT ==="

FAILED=0

rm -rf bin

if just build; then
    echo "  ✅ wails3 build completed"
else
    echo "  ❌ wails3 build failed"
    exit 1
fi

echo ""
echo "=== a Linux binary exists ==="
BIN=""
for candidate in bin/booth-counter bin/*; do
    if [[ -f "$candidate" && -x "$candidate" && "$candidate" != *.exe ]]; then
        BIN="$candidate"
        break
    fi
done
# wails3 may write to build/bin as well
if [[ -z "$BIN" ]]; then
    for candidate in build/bin/booth-counter build/bin/*; do
        if [[ -f "$candidate" && -x "$candidate" && "$candidate" != *.exe ]]; then
            BIN="$candidate"
            break
        fi
    done
fi

if [[ -n "$BIN" && -s "$BIN" ]]; then
    echo "  ✅ $BIN ($(wc -c < "$BIN") bytes)"
    if file "$BIN" | grep -qiE 'ELF|Linux'; then
        echo "  ✅ $BIN is an ELF/Linux binary"
    else
        echo "  ⚠️  file(1) did not call it ELF: $(file "$BIN")"
    fi
else
    echo "  ❌ no Linux binary under bin/ or build/bin"
    ls -la bin build/bin 2>/dev/null || true
    FAILED=1
fi

echo ""
echo "=== the app's own UI string reached the binary ==="
if [[ -n "$BIN" ]] && grep -q "Booth counter" "$BIN"; then
    echo "  ✅ 'Booth counter' is present in $BIN"
else
    echo "  ❌ 'Booth counter' is missing from the binary (frontend not embedded?)"
    FAILED=1
fi

exit $FAILED
