#!/bin/bash
set -e

BIN="zig-out/bin/snake"

if [ ! -f "$BIN" ]; then
    echo "Building snake..."
    zig build
fi

exec "$BIN" "$@"
