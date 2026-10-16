#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Sweeps every scratch location a config-tui run leaves behind. The prj--*/log--*
# pair moved out of tests/config-tui/ and under $TMPDIR with tui-helpers--source.sh
# (which owns the path), so the in-tree globs below only matter for leftovers from
# before that move; the out-of-tree ones are where a run writes today, including
# the *--attempt1 copies run-all-tests.sh keeps of a retried test's first attempt.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_scratch_base="${TMPDIR:-/tmp}/codingbooth-config-tui-tests"

rm -rf "${_scratch_base}"/prj--* "${_scratch_base}"/log--*.log
rm -rf "$SCRIPT_DIR"/prj--* "$SCRIPT_DIR"/log--* "$SCRIPT_DIR"/run--*
echo "Cleaned."
