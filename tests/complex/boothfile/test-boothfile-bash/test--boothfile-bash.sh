#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile GNU Bash (a second shell, default 3.2.57)
#
# bash-3.2 --version proves the binary. The safe probe is what a script must
# do to run under the bash 3.2 that macOS ships. The unsafe probe is the
# expansion that shell rejects.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile GNU Bash Installation ==="

FAILED=0

ACTUAL=$(capture_codingbooth "head -1" --silence-build -- bash-3.2 --version)
if echo "$ACTUAL" | grep -q "3.2.57"; then
    print_test_result "true" "$0" "1" "bash-3.2 reports 3.2.57"
else
    print_test_result "false" "$0" "1" "bash-3.2 should report 3.2.57"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# The image login shell stays the distro bash.
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- bash --version)
if echo "$ACTUAL" | grep -q "GNU bash" && ! echo "$ACTUAL" | grep -q "3.2.57"; then
    print_test_result "true" "$0" "2" "/bin/bash is still the distro bash"
else
    print_test_result "false" "$0" "2" "/bin/bash should stay the distro bash"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'bash-3.2 ./probe-safe.sh')
if echo "$ACTUAL" | grep -q "survived"; then
    print_test_result "true" "$0" "3" "bash-3.2 accepts the empty-array form"
else
    print_test_result "false" "$0" "3" "bash-3.2 should accept the empty-array form"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# The unsafe script exits non-zero. The wrapper still prints rc so the
# capture is not empty (an empty capture is retried and hides the failure).
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'bash-3.2 ./probe-unsafe.sh > /tmp/bash-unsafe.out 2> /tmp/bash-unsafe.err; echo rc:$?; cat /tmp/bash-unsafe.err; echo ---; cat /tmp/bash-unsafe.out')
if echo "$ACTUAL" | grep -q "unbound variable" && ! echo "$ACTUAL" | grep -q "survived"; then
    print_test_result "true" "$0" "4" "bash-3.2 rejects an empty array under set -u"
else
    print_test_result "false" "$0" "4" "bash-3.2 should reject an empty array under set -u"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
