#!/bin/sh
set -e

OS=${1:-darwin}
ARCH=${2:-arm64}

case "${OS}-${ARCH}" in
    darwin-arm64|darwin-aarch64)
        export CC=zcc-darwin-arm64
        export GOARCH=arm64
        export GOOS=darwin
        ;;
    darwin-amd64|darwin-x86_64)
        export CC=zcc-darwin-amd64
        export GOARCH=amd64
        export GOOS=darwin
        ;;
    linux-arm64|linux-aarch64)
        export CC=gcc
        export GOARCH=arm64
        export GOOS=linux
        ;;
    linux-amd64|linux-x86_64)
        export CC=gcc
        export GOARCH=amd64
        export GOOS=linux
        ;;
    windows-arm64|windows-aarch64)
        export CC=zcc-windows-arm64
        export GOARCH=arm64
        export GOOS=windows
        ;;
    windows-amd64|windows-x86_64)
        export CC=zcc-windows-amd64
        export GOARCH=amd64
        export GOOS=windows
        ;;
    *)
        echo "Usage: <os> <arch>"
        echo "  os: darwin, linux, windows"
        echo "  arch: amd64, arm64"
        exit 1
        ;;
esac

export CGO_ENABLED=1
export CGO_CFLAGS="-w"

# Build frontend if exists and not already built (host may have built it)
if [ -d "frontend" ] && [ -f "frontend/package.json" ] && [ ! -d "frontend/dist" ]; then
    (cd frontend && npm install --silent && npm run build --silent)
fi

# Build
APP=${APP_NAME:-$(basename $(pwd))}
mkdir -p bin

EXT=""
LDFLAGS="-s -w"
if [ "$GOOS" = "windows" ]; then
    EXT=".exe"
    LDFLAGS="-s -w -H windowsgui"
fi

TAGS="production"
if [ -n "$EXTRA_TAGS" ]; then
    TAGS="${TAGS},${EXTRA_TAGS}"
fi

COMPILER="go build"
if [ "$OBFUSCATED" = "true" ]; then
    COMPILER="garble ${GARBLE_ARGS} build"
    TAGS="${TAGS},wails_obfuscated"
fi

${COMPILER} -tags "$TAGS" -trimpath -buildvcs=false -ldflags="$LDFLAGS" -o bin/${APP}-${GOOS}-${GOARCH}${EXT} .
echo "Built: bin/${APP}-${GOOS}-${GOARCH}${EXT}"
