#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Failure branches of mojo-nb-kernel--setup.sh. The success path writes
# /usr/share/startup.d and a kernelspec as root — that is the complex
# boothfile test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/mojo-nb-kernel--setup.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/opt/python/bin"

write_python_stub() {
    cat > "$STUB/opt/python/bin/python" << 'EOF'
#!/bin/bash
echo "STUB_PYTHON $*" >> "$STUB_LOG"
if [[ "${1:-}" == "-c" ]]; then
    if [[ "${2:-}" == *"mojo.notebook"* ]]; then
        [[ "${STUB_HAS_NOTEBOOK:-yes}" == "yes" ]] && exit 0
        exit 1
    fi
    if [[ "${2:-}" == *"ipykernel"* ]]; then
        [[ "${STUB_HAS_JUPYTER:-yes}" == "yes" ]] && exit 0
        exit 1
    fi
    exit 0
fi
exit 0
EOF
    chmod +x "$STUB/opt/python/bin/python"
}

write_python_stub
cat > "$STUB/opt/python/bin/mojo" << 'EOF'
#!/bin/sh
echo "mojo stub"
EOF
chmod +x "$STUB/opt/python/bin/mojo"
ln -sfn "$STUB/opt/python/bin/mojo" "$STUB/bin/mojo"

run_setup() {
    local extra="$1"; shift
    : > "$STUB/log"
    # shellcheck disable=SC2086
    env $extra \
        PATH="$STUB/bin:/usr/bin:/bin" \
        STUB_LOG="$STUB/log" \
        CB_PYTHON_HOME="$STUB/opt/python" \
        EUID=0 \
        bash "$SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

# 1. Missing Python.
rm -f "$STUB/opt/python/bin/python"
out=$(run_setup "") && rc=0 || rc=$?
if [[ $rc -ne 0 ]] && echo "$out" | grep -q "Python is not set up"; then
    print_test_result "true" "$0" "1" "missing python fails"
else
    print_test_result "false" "$0" "1" "missing python fails"
    echo "  rc=$rc output=$out"
    ALL_PASSED=false
fi
write_python_stub

# 2. mojo.notebook missing from the installed package.
out=$(run_setup "STUB_HAS_NOTEBOOK=no") && rc=0 || rc=$?
if [[ $rc -ne 0 ]] && echo "$out" | grep -q "mojo.notebook"; then
    print_test_result "true" "$0" "2" "missing mojo.notebook fails"
else
    print_test_result "false" "$0" "2" "missing mojo.notebook fails"
    echo "  rc=$rc output=$out"
    ALL_PASSED=false
fi

# 3. Jupyter/ipykernel missing.
out=$(run_setup "STUB_HAS_JUPYTER=no") && rc=0 || rc=$?
if [[ $rc -eq 2 ]] && echo "$out" | grep -q "notebook--setup.sh"; then
    print_test_result "true" "$0" "3" "missing jupyter fails with exit 2"
else
    print_test_result "false" "$0" "3" "missing jupyter fails with exit 2"
    echo "  rc=$rc output=$out"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" == true ]]; then
    echo "✅ All tests passed"
    exit 0
fi
echo "❌ Some tests failed"
exit 1
