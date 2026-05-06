#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile RabbitMQ Installation
#
# Verifies that a Boothfile with `setup rabbitmq --version latest` installs the
# rabbitmq-server package. The broker daemon is not validated (only transiently
# started during build); we check binary presence on PATH.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile RabbitMQ Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- ls /usr/sbin/rabbitmq-server 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qE '/rabbitmq-server$'; then
    print_test_result "true" "$0" "1" "RabbitMQ is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "RabbitMQ should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
