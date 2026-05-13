#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile bash-nb-kernel Installation
#
# Verifies that `setup notebook` + `setup bash-nb-kernel` registers a Bash
# kernel with Jupyter. We don't launch JupyterLab — `jupyter kernelspec list`
# is enough to confirm the kernelspec is present.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile bash-nb-kernel Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- jupyter kernelspec list 2>&1 | grep -v '^> codingbooth' || true)

if echo "$ACTUAL" | grep -qiE '^\s*bash\s'; then
    print_test_result "true" "$0" "1" "bash kernel is registered with Jupyter"
else
    print_test_result "false" "$0" "1" "bash kernel should be listed by 'jupyter kernelspec list'"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
