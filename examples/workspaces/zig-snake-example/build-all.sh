#!/bin/bash
set -e

# Cross-compile the snake game to multiple platforms.
# The game uses POSIX terminal APIs (termios, poll), so only Unix targets are supported.

# Clean up build artifacts
rm -rf zig-out
rm -rf dist

TARGETS=(
    "x86_64-linux-gnu"
    "aarch64-linux-gnu"
    "x86_64-linux-musl"
    "aarch64-linux-musl"
    "x86_64-macos"
    "aarch64-macos"
)

mkdir -p zig-out
mkdir -p dist

for target in "${TARGETS[@]}"; do
    echo "Building for $target..."
    zig build -Dtarget="$target" -Doptimize=ReleaseSafe

    # Derive a short name for the output binary
    name="snake-${target}"
    cp "zig-out/bin/snake" "dist/${name}"
done

echo ""
echo "Done! Binaries in dist/"
ls -lh dist/

# Clean up build artifacts
rm -rf zig-out
