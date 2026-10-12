#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile exec env — setups usable from `booth exec` without a login shell
#
# The booth is configured with plain `--select go/julia/java/conda`. Each of these setups put
# PATH entries or variables only in /etc/profile.d, which `booth exec` never reads. Their
# templates now repeat them as image `env` lines; tests/config/catalog/test137 checks that
# statically, this checks it in a running booth (inBooth-exec-env.sh):
#   1-3. julia, conda and the go template's own gopls are found;
#   4-7. GOPATH, JAVA_HOME (a working JDK), JULIA_DEPOT_PATH and CONDA_ENVS_DIRS are set.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile exec env ==="

FAILED=0
ACTUAL=$(run_coding_booth exec --run --silence-build -- bash inBooth-exec-env.sh 2>/dev/null) || ACTUAL=""

# check <num> <label> <pattern> <description>: the line "<label>: ..." matches the pattern.
check() {
    local num="$1" label="$2" pattern="$3" desc="$4" line
    line=$(echo "$ACTUAL" | grep "^${label}: " | head -1)
    if echo "$line" | grep -qE -- "^${label}: ${pattern}"; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "  Actual line: ${line:-<none>}"
        FAILED=$((FAILED + 1))
    fi
}

check 1 julia       'julia version '              "booth exec finds julia"
check 2 conda       'conda [0-9]'                 "booth exec finds conda"
check 3 gopls       'ok$'                         "booth exec finds the go template's gopls"
check 4 gopath      '/home/coder/go$'             "GOPATH is set"
check 5 java-home   '(openjdk|java) version '     "JAVA_HOME points at a working JDK"
check 6 julia-depot '/home/coder/\.julia$'        "JULIA_DEPOT_PATH is set"
check 7 conda-envs  '/opt/conda-envs$'            "CONDA_ENVS_DIRS is set"

if [[ $FAILED -ne 0 ]]; then
    echo "  Full output:"; echo "$ACTUAL" | sed 's/^/    /'
fi
exit $FAILED
