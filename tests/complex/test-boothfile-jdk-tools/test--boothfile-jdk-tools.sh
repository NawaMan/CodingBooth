#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: `setup jdk` puts its command-line tools on PATH in a NON-LOGIN shell.
#
# The non-login part is the whole test. jdk--setup.sh wires JAVA_HOME/bin onto
# PATH through /etc/profile.d, which a login shell reads and `booth -- ./script`
# does not — it runs via `runuser -u coder --`. What actually reaches a script is
# whatever the setup registered with update-alternatives under /usr/bin.
#
# keytool and jarsigner were missing from that list, so signing anything from a
# script (an Android APK, a JAR, a self-signed cert) failed with "command not
# found" while working perfectly in an interactive shell — the kind of gap that
# only shows up in automation.
#
# Test 1 is docker-free. Tests 2+ build a real image and run only when a locally
# rebuilt base image is present.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: setup jdk command-line tools on a non-login shell ==="

FAILED=0

BOOTH_PATH=""
CHECK_DIR="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -f "$CHECK_DIR/codingbooth" && -x "$CHECK_DIR/codingbooth" ]]; then
        BOOTH_PATH="$CHECK_DIR/codingbooth"
        break
    fi
    CHECK_DIR="$(dirname "$CHECK_DIR")"
done
if [[ -z "$BOOTH_PATH" ]]; then
    echo "ERROR: Could not find codingbooth"
    exit 1
fi

DOCKERFILE=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" 2>&1) || true

# Test 1: the setup compiles.
if echo "$DOCKERFILE" | grep -qE "RUN jdk--setup\.sh 17 temurin"; then
    print_test_result "true" "$0" "1" "setup jdk compiles to RUN jdk--setup.sh"
else
    print_test_result "false" "$0" "1" "setup jdk should compile to RUN jdk--setup.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

use_local_base_image || exit $FAILED

# Test 2: every tool resolves without a login shell. keytool and jarsigner are
# the regression guards; the rest confirm nothing else fell out of the list.
MISSING=$(run_coding_booth --silence-build -- \
    'for t in java javac jar jcmd jps jstack keytool jarsigner; do command -v $t >/dev/null 2>&1 || echo $t; done' \
    2>/dev/null | tr -d '\r' | tr '\n' ' ' | xargs || true)
if [[ -z "$MISSING" ]]; then
    print_test_result "true" "$0" "2" "java/javac/jar/jcmd/jps/jstack/keytool/jarsigner all resolve in a non-login shell"
else
    print_test_result "false" "$0" "2" "some JDK tools do not resolve in a non-login shell"
    echo "  Missing: $MISSING"
    FAILED=$((FAILED + 1))
fi

# Test 3: keytool does not merely exist, it runs. A dangling alternatives symlink
# would still satisfy `command -v`.
ACTUAL=$(run_coding_booth --silence-build -- 'keytool -help 2>&1 | head -1' 2>/dev/null | tr -d '\r') || ACTUAL=""
if echo "$ACTUAL" | grep -qi "key"; then
    print_test_result "true" "$0" "3" "keytool executes"
else
    print_test_result "false" "$0" "3" "keytool should execute"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: it can actually create a keystore — what APK/JAR signing needs of it.
ACTUAL=$(run_coding_booth --silence-build -- \
    'keytool -genkeypair -keystore /tmp/cb-test.jks -storepass changeit -keypass changeit -alias t -keyalg RSA -keysize 2048 -validity 1 -dname "CN=T,O=T,C=US" >/dev/null 2>&1 && test -s /tmp/cb-test.jks && echo KEYSTORE_OK' \
    2>/dev/null | tr -d '\r' | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "KEYSTORE_OK" ]]; then
    print_test_result "true" "$0" "4" "keytool generates a keystore"
else
    print_test_result "false" "$0" "4" "keytool should generate a keystore"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
