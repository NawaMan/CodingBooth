#!/bin/bash
set -e

BUILD=false
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--build" ]; then
        BUILD=true
    else
        ARGS+=("$arg")
    fi
done

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

if [ "$BUILD" = true ]; then
    # Determine the zig target for the current platform
    if [ "$OS" = "linux" ]; then
        TARGET="${ARCH}-linux-gnu"
    else
        TARGET="${ARCH}-${OS}"
    fi
    BIN_NAME="snake-${TARGET}"

    echo "Building for $TARGET..."
    rm -rf zig-out
    mkdir -p dist
    zig build -Dtarget="$TARGET" -Doptimize=ReleaseSafe
    cp "zig-out/bin/snake" "dist/${BIN_NAME}"
    rm -rf zig-out

    # Delete other binaries in dist/
    for f in dist/snake-*; do
        [ -f "$f" ] || continue
        if [ "$(basename "$f")" != "$BIN_NAME" ]; then
            rm -f "$f"
        fi
    done

    echo "Built dist/${BIN_NAME}"
    BIN="dist/${BIN_NAME}"
else
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
        echo "Run ./build-all.sh or ./run-snake.sh --build first, or check dist/ for available binaries:"
        ls dist/ 2>/dev/null || echo "  (dist/ not found)"
        exit 1
    fi
fi

exec "$BIN" "${ARGS[@]}"
