#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Sweeps every scratch location a config-test run leaves behind, both already
# out of tests/config/ itself: the out-of-tree prj--*/log--*.log
# (test-helpers--source.sh's own scratch, under $TMPDIR) and the captured
# out--*.log per parallel test (run-all-tests.sh's capture_file(), under
# tests/logs/config/). Nothing to clean inside tests/config/ itself anymore —
# this exists for the rare case of wanting those gone too, between runs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_scratch_base="${TMPDIR:-/tmp}/codingbooth-config-tests"

rm -rf "${_scratch_base}"/prj--* "${_scratch_base}"/log--*.log
rm -rf "${SCRIPT_DIR}/../logs/config"
echo "Cleaned."
