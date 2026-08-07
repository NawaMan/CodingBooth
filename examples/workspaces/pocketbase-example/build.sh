#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Build the Tripboard server. Run this inside the booth, where the pinned Go
# toolchain lives.
#
# The result is one static binary: PocketBase is compiled in, SQLite and all.
# The first build downloads the dependency tree and takes a minute; later ones
# are seconds.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "Building tripboard..."
go build -o tripboard .

echo "Built: $ROOT_DIR/tripboard"
