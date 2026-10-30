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

# Resolve build/ before changing directory, so sibling scripts stay reachable
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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


# Stamped into main.buildDate via ldflags below, so a rebuilt-but-unbumped dev
# binary (version.txt unchanged) is still distinguishable in the config TUI
# header from whatever a project's wrapper/cache had already resolved.
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# The apt snapshot this release's images are built against, stamped in as the
# snapshot a new booth is frozen to — so a fresh booth is never older than its
# own image. Resolved exactly as docker-build.sh resolves it (CB_APT_SNAPSHOT,
# else apt-snapshot.txt, else a week back), so the two cannot disagree.
APT_SNAPSHOT=$(
    cd "${SCRIPT_DIR}/.." &&
    source build/apt-snapshot--source.sh &&
    resolve_apt_snapshot &&
    echo "$APT_SNAPSHOT"
) || { echo "❌ Error: could not resolve the apt snapshot to stamp in"; exit 1; }

LDFLAGS="-X main.version=${VERSION} -X main.buildDate=${BUILD_DATE}"
LDFLAGS+=" -X github.com/nawaman/codingbooth/src/pkg/boothinit/aptsnapshot.Release=${APT_SNAPSHOT}"

echo "🔨 Building ${APP_NAME} v${VERSION} (apt snapshot ${APT_SNAPSHOT})"
echo "=================================="
echo ""

# Refresh the embedded built-in script list so `setup`/`install` name validation
# matches what the base image actually ships.
echo "🧾 Refreshing embedded built-in script list..."
"${SCRIPT_DIR}/gen-builtin-scripts.sh"
echo ""

# Download dependencies
echo "📥 Downloading dependencies..."
go mod download
echo ""
echo "🧳 Packing the kit booth prepare embeds (variants, docs, experiments/host-provision)..."
go run ./src/cmd/prepare-kit --root .. --out src/pkg/prepare/kit/kit.tar.gz
echo ""

# The binary trusts what its Go toolchain's crypto/x509 trusts, so an older Go
# ships a CLI that still accepts the compromised eMudhra CA keys. go.mod's
# toolchain line makes the go command switch to it (GOTOOLCHAIN=auto, the
# default); GOTOOLCHAIN=local would silently keep an older one, so check.
MIN_GO=$(sed -n 's/^toolchain go//p' go.mod)
USED_GO=$(go env GOVERSION); USED_GO=${USED_GO#go}
if [[ -n "$MIN_GO" ]] && [[ "$(printf '%s\n%s\n' "$MIN_GO" "$USED_GO" | sort -V | head -1)" != "$MIN_GO" ]]; then
    echo "❌ Error: building with Go ${USED_GO}, but go.mod requires toolchain go${MIN_GO}."
    echo "   Upgrade Go, or unset GOTOOLCHAIN=local so the go command can fetch it."
    exit 1
fi

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

BUILD_OUTPUT=$(go build -ldflags "${LDFLAGS}" -o "$LOCAL_OUTPUT" "$SRC_DIR/codingbooth" 2>&1) && BUILD_SUCCESS=true || BUILD_SUCCESS=false
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
    
    BUILD_OUTPUT=$(GOOS=$GOOS GOARCH=$GOARCH go build -ldflags "${LDFLAGS}" -o "$OUTPUT_PATH" "$SRC_DIR/codingbooth" 2>&1) && BUILD_SUCCESS=true || BUILD_SUCCESS=false
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

# An unreleased version (x.y.z--rc1, x.y.z--<worktree>) has nothing to download,
# so the examples' ./booth runs this build from the shared cache instead.
if [[ $FAILED_COUNT -eq 0 && "$VERSION" == *--* ]]; then
    echo ""
    "${SCRIPT_DIR}/../examples/update-booth.sh" --seed-only
fi
