#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile GNU Bash 5.3 (bash:5.3, a second shell)
#
# The modern counterpart of test-boothfile-bash. 5.3 compiles as C23, so it
# takes the build path with no CFLAGS pin. The distro bash may also be 5.3,
# so the binary is told apart by where it resolves, not by its version. The
# unsafe probe that bash 3.2 rejects runs fine here.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile GNU Bash 5.3 Installation ==="

FAILED=0

ACTUAL=$(capture_codingbooth "head -1" --silence-build -- bash-5.3 --version)
if echo "$ACTUAL" | grep -q "version 5\.3\."; then
    print_test_result "true" "$0" "1" "bash-5.3 reports 5.3"
else
    print_test_result "false" "$0" "1" "bash-5.3 should report 5.3"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'readlink -f "$(command -v bash-5.3)"; readlink -f /bin/bash')
if echo "$ACTUAL" | head -1 | grep -q "^/opt/bash/bash-5\.3/bin/bash$" \
        && ! echo "$ACTUAL" | tail -1 | grep -q "^/opt/bash/"; then
    print_test_result "true" "$0" "2" "bash-5.3 is the source build and /bin/bash is still the distro bash"
else
    print_test_result "false" "$0" "2" "bash-5.3 should be the source build and /bin/bash the distro bash"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'bash-5.3 ./probe-safe.sh')
if echo "$ACTUAL" | grep -q "survived"; then
    print_test_result "true" "$0" "3" "bash-5.3 accepts the guarded empty-array form"
else
    print_test_result "false" "$0" "3" "bash-5.3 should accept the guarded empty-array form"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# The form bash 3.2 rejects. Bash 4.4 and later expand an empty array to
# nothing under set -u. rc is printed so the capture is never empty.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'bash-5.3 ./probe-unsafe.sh 2>&1; echo rc:$?')
if echo "$ACTUAL" | grep -q "survived" && echo "$ACTUAL" | grep -q "rc:0" \
        && ! echo "$ACTUAL" | grep -q "unbound variable"; then
    print_test_result "true" "$0" "4" "bash-5.3 accepts an empty array under set -u"
else
    print_test_result "false" "$0" "4" "bash-5.3 should accept an empty array under set -u"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
