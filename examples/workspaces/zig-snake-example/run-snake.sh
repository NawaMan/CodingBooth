#!/bin/bash
set -e

ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

case "$OS" in
    linux)  OS="linux" ;;
    darwin) OS="macos" ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Try gnu first, fall back to musl on Linux
if [ "$OS" = "linux" ]; then
    BIN="dist/snake-${ARCH}-linux-gnu"
    if [ ! -f "$BIN" ]; then
        BIN="dist/snake-${ARCH}-linux-musl"
    fi
else
    BIN="dist/snake-${ARCH}-${OS}"
fi

if [ ! -f "$BIN" ]; then
    echo "No binary found for ${ARCH}-${OS}"
    echo "Run ./build-all.sh first, or check dist/ for available binaries:"
    ls dist/ 2>/dev/null || echo "  (dist/ not found)"
    exit 1
fi

exec "$BIN" "$@"
