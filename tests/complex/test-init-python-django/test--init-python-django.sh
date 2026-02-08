#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Init-generated Python + Django workspace
#
# Verifies that a booth init generated Boothfile with python and django
# correctly installs both Python and the Django framework.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Init-generated Python + Django workspace ==="

FAILED=0

# Test 1: Python is installed
PY_ACTUAL=$(run_coding_booth --silence-build -- python3 --version 2>/dev/null | head -1)

if echo "$PY_ACTUAL" | grep -qE "Python 3\.12"; then
    print_test_result "true" "$0" "1" "Python 3.12 is installed"
else
    print_test_result "false" "$0" "1" "Python 3.12 should be installed"
    echo "  Actual output: $PY_ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: Django is installed via pip
DJANGO_ACTUAL=$(run_coding_booth --silence-build -- python3 -m django --version 2>/dev/null | head -1) || true

if echo "$DJANGO_ACTUAL" | grep -qE "^[0-9]+\."; then
    print_test_result "true" "$0" "2" "Django is installed"
else
    print_test_result "false" "$0" "2" "Django should be installed via pip"
    echo "  Actual output: $DJANGO_ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: django-admin is available
ADMIN_ACTUAL=$(run_coding_booth --silence-build -- django-admin --version 2>/dev/null | head -1) || true

if echo "$ADMIN_ACTUAL" | grep -qE "^[0-9]+\."; then
    print_test_result "true" "$0" "3" "django-admin is available"
else
    print_test_result "false" "$0" "3" "django-admin should be available"
    echo "  Actual output: $ADMIN_ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
