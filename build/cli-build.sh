#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


set -euo pipefail

# Build configuration
APP_NAME="codingbooth"
SRC_DIR="./src/cmd"
OUTPUT_DIR="../bin"
VERSION_FILE="../version.txt"

# Change to cli directory where go.mod is located (from build/ go up one level)
cd "$(dirname "$0")/../cli" || exit 1

# Validate we're in the correct directory structure
if [[ ! -f "go.mod" ]] || [[ ! -f "$VERSION_FILE" ]]; then
    echo "❌ Error: This script must be run from the project root directory."
    echo "   Usage: ./build/cli-build.sh"
    exit 1
fi

# Read version from version.txt
if [[ -f "$VERSION_FILE" ]]; then
    VERSION=$(tr -d ' \t\n\r' < "$VERSION_FILE")
else
    echo "❌ Error: $VERSION_FILE not found"
    exit 1
fi

echo "🔨 Building ${APP_NAME} v${VERSION}"
echo "=================================="
echo ""

# Download dependencies
echo "📥 Downloading dependencies..."
go mod download
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Build matrix: OS and Architecture combinations
declare -a PLATFORMS=(
    "linux/amd64"
    "linux/arm64"
    "darwin/amd64"
    "darwin/arm64"
    "windows/amd64"
    "windows/arm64"
)

echo "📦 Building for multiple platforms..."
echo ""

# First, build for the current platform and place in project root
echo "🏠 Building local executable for current platform..."
LOCAL_OUTPUT="../codingbooth"
if [[ "$(uname -s)" == "MINGW"* ]] || [[ "$(uname -s)" == "CYGWIN"* ]] || [[ "$(uname -s)" == "MSYS"* ]]; then
    LOCAL_OUTPUT="../codingbooth.exe"
fi

BUILD_OUTPUT=$(go build -ldflags "-X main.version=${VERSION}" -o "$LOCAL_OUTPUT" "$SRC_DIR/codingbooth" 2>&1) && BUILD_SUCCESS=true || BUILD_SUCCESS=false
if $BUILD_SUCCESS; then
    LOCAL_SIZE=$(du -h "$LOCAL_OUTPUT" | cut -f1)
    echo "   ✅ Built: $LOCAL_OUTPUT (${LOCAL_SIZE})"
else
    echo "   ❌ FAILED to build local executable"
    echo "$BUILD_OUTPUT" | sed 's/^/      /'
fi
echo ""

echo "🌍 Building for all platforms..."
echo ""

BUILD_COUNT=0
FAILED_COUNT=0

for PLATFORM in "${PLATFORMS[@]}"; do
    # Split platform into OS and ARCH
    IFS='/' read -r GOOS GOARCH <<< "$PLATFORM"
    
    # Determine output filename
    OUTPUT_NAME="${APP_NAME}-${GOOS}-${GOARCH}"
    if [[ "$GOOS" == "windows" ]]; then
        OUTPUT_NAME="${OUTPUT_NAME}.exe"
    fi
    
    OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_NAME}"
    
    # Build
    echo -n "   Building ${GOOS}/${GOARCH}... "
    
    BUILD_OUTPUT=$(GOOS=$GOOS GOARCH=$GOARCH go build -ldflags "-X main.version=${VERSION}" -o "$OUTPUT_PATH" "$SRC_DIR/codingbooth" 2>&1) && BUILD_SUCCESS=true || BUILD_SUCCESS=false
    if $BUILD_SUCCESS; then
        SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
        echo "✅ (${SIZE})"
        BUILD_COUNT=$((BUILD_COUNT + 1))
    else
        echo "❌ FAILED"
        echo "$BUILD_OUTPUT" | sed 's/^/      /'
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# Build booth-ws-bridge (container-only binary, Linux only)
BRIDGE_NAME="booth-ws-bridge"
BRIDGE_PLATFORMS=("linux/amd64" "linux/arm64")

echo ""
echo "🌉 Building ${BRIDGE_NAME} (container binary)..."
echo ""

for PLATFORM in "${BRIDGE_PLATFORMS[@]}"; do
    IFS='/' read -r GOOS GOARCH <<< "$PLATFORM"
    OUTPUT_PATH="${OUTPUT_DIR}/${BRIDGE_NAME}-${GOOS}-${GOARCH}"

    echo -n "   Building ${GOOS}/${GOARCH}... "

    BUILD_OUTPUT=$(CGO_ENABLED=0 GOOS=$GOOS GOARCH=$GOARCH go build -ldflags "-s -w" -o "$OUTPUT_PATH" "$SRC_DIR/booth-ws-bridge" 2>&1) && BUILD_SUCCESS=true || BUILD_SUCCESS=false
    if $BUILD_SUCCESS; then
        SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
        echo "✅ (${SIZE})"
        BUILD_COUNT=$((BUILD_COUNT + 1))
    else
        echo "❌ FAILED"
        echo "$BUILD_OUTPUT" | sed 's/^/      /'
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""
echo "=================================="
echo "📊 Build Summary"
echo "=================================="
echo "   Successful: ${BUILD_COUNT}"
echo "   Failed:     ${FAILED_COUNT}"
echo "   Total:      $(( ${#PLATFORMS[@]} + ${#BRIDGE_PLATFORMS[@]} ))"
echo ""

if [[ $FAILED_COUNT -eq 0 ]]; then
    echo "✅ All builds completed successfully!"
else
    echo "⚠️  Some builds failed. Check the output above."
fi

echo ""
echo "📂 Build artifacts in: ${OUTPUT_DIR}/"
echo ""
ls -lh "$OUTPUT_DIR"

echo ""
echo "🎉 Build complete!"
