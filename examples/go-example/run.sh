#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT_DIR/bin"

# Derive effective target just like build.sh
GOOS=${GOOS:-}
GOARCH=${GOARCH:-}
TARGET_OS=${GOOS:-$(go env GOOS)}
TARGET_ARCH=${GOARCH:-$(go env GOARCH)}

BIN_NAME="treemoji-${TARGET_OS}-${TARGET_ARCH}"
if [[ "$TARGET_OS" == "windows" ]]; then
  BIN_NAME="${BIN_NAME}.exe"
fi

BIN_PATH="$BIN_DIR/$BIN_NAME"

# Build first if binary does not exist
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Binary $BIN_NAME not found, building..."
  GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" "$ROOT_DIR/build.sh"
fi

exec "$BIN_PATH" "$@"
