#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Regenerates build/catalog-manifest.tsv: one row per catalog item (setup, install,
# helper, lib, asset dir, template, extension) with its hand-written cb-version and
# its sha256. Run after changing anything under variants/base/setups/ or templates/.
#
#   build/gen-catalog-manifest.sh            # write the manifest
#   build/gen-catalog-manifest.sh --check    # verify only; exit 1 if stale or a cb-version is missing
#
# See docs/CATALOG_VERSIONING.md.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}/cli"
exec go run ./src/cmd/catalog-manifest generate --root "${ROOT}" "$@"
