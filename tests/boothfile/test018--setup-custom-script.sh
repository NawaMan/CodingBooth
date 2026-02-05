#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: custom setup script from .booth/setups/ auto-generates COPY

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth/setups"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

setup myapp
EOF

cat > "$TEST_DIR/.booth/setups/myapp--setup.sh" << 'EOF'
#!/bin/bash
echo "Setting up myapp"
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# Should have COPY for custom setups directory
if echo "$ACTUAL" | grep -qE "COPY .booth/setups/ /home/coder/.booth/setups/"; then
    print_test_result "true" "$0" "018" "Custom setups directory copied"
else
    print_test_result "false" "$0" "018" "Custom setups directory copied"
    ALL_PASSED=false
fi

# Should have PATH update
if echo "$ACTUAL" | grep -qF "ENV PATH=/home/coder/.booth/setups:\$PATH"; then
    print_test_result "true" "$0" "018" "Custom setups added to PATH"
else
    print_test_result "false" "$0" "018" "Custom setups added to PATH"
    ALL_PASSED=false
fi

# Should have RUN for the script
if echo "$ACTUAL" | grep -qF "RUN myapp--setup.sh"; then
    print_test_result "true" "$0" "018" "Custom setup script generates RUN"
else
    print_test_result "false" "$0" "018" "Custom setup script generates RUN"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
