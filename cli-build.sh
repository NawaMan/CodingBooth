#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


set -euo pipefail

# Build configuration
APP_NAME="coding-booth"
SRC_DIR="./src/cmd"
OUTPUT_DIR="../bin"
VERSION_FILE="../version.txt"

# Change to cli directory where go.mod is located
cd "$(dirname "$0")/cli" || exit 1

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
LOCAL_OUTPUT="../coding-booth"
if [[ "$(uname -s)" == "MINGW"* ]] || [[ "$(uname -s)" == "CYGWIN"* ]] || [[ "$(uname -s)" == "MSYS"* ]]; then
    LOCAL_OUTPUT="../coding-booth.exe"
fi

if go build -ldflags "-X main.version=${VERSION}" -o "$LOCAL_OUTPUT" "$SRC_DIR/coding-booth" 2>/dev/null; then
    LOCAL_SIZE=$(du -h "$LOCAL_OUTPUT" | cut -f1)
    echo "   ✅ Built: $LOCAL_OUTPUT (${LOCAL_SIZE})"
else
    echo "   ❌ FAILED to build local executable"
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
    
    if GOOS=$GOOS GOARCH=$GOARCH go build -ldflags "-X main.version=${VERSION}" -o "$OUTPUT_PATH" "$SRC_DIR/coding-booth" 2>/dev/null; then
        SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
        echo "✅ (${SIZE})"
        BUILD_COUNT=$((BUILD_COUNT + 1))
    else
        echo "❌ FAILED"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""
echo "=================================="
echo "📊 Build Summary"
echo "=================================="
echo "   Successful: ${BUILD_COUNT}"
echo "   Failed:     ${FAILED_COUNT}"
echo "   Total:      ${#PLATFORMS[@]}"
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
