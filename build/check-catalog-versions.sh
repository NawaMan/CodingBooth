#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Release check for catalog versions: compares every catalog item against the
# manifest at the previous release tag. Fails when an item changed but kept its
# cb-version, when a version went down, when a template's params were removed or
# reordered without a breaking bump, or when build/catalog-manifest.tsv is stale.
#
#   build/check-catalog-versions.sh                    # blocking (release-push, CI)
#   build/check-catalog-versions.sh --report           # report only — during development
#   build/check-catalog-versions.sh --baseline 0.79.0  # compare against a specific ref
#
# See docs/CATALOG_VERSIONING.md.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}/cli"
exec go run ./src/cmd/catalog-manifest check --root "${ROOT}" "$@"
