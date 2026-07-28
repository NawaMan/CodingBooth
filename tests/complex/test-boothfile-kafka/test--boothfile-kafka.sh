#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Kafka Installation
#
# Verifies that a Boothfile with `setup kafka --version 3.7.0` lays down the
# Kafka install at /opt/kafka. The broker daemon is not validated (it's only
# transiently started during build); we check binary presence in /opt/kafka.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Kafka Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- /opt/kafka/bin/kafka-topics.sh --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
    print_test_result "true" "$0" "1" "Kafka is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Kafka should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
