#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile `setup android-sdk`
#
# Verifies that:
#   1. android-sdk is a recognized setup (compiles to RUN android-sdk--setup.sh)
#   2. It is ordered after the JDK, which sdkmanager needs to run at all
#   3. In a real build, the SDK tools are on PATH in a NON-LOGIN shell
#   4. aapt2 and adb actually execute (present != working)
#   5. android.jar for the configured API is installed and readable by coder
#
# Tests 1-2 are docker-free (emit-dockerfile only). Tests 3-5 build a real image
# and run only when a locally-rebuilt base image is present, because
# android-sdk--setup.sh is new and not yet baked into the Docker Hub base image.
#
# NOT COVERED HERE: `setup android-emulator`. Its system image is multiple
# gigabytes, which is more than this suite should download per run. Its
# generated output is covered by tests/config/test93-init-android-sdk.sh, and
# the install itself has to be exercised by hand:
#
#   booth config <dir> --select java:17/android-sdk+emulator+kvm
#   booth -- bash -c 'emulator -accel-check && emulator -version'
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile setup android-sdk ==="

FAILED=0

# Locate the codingbooth binary for the docker-free emit-dockerfile checks.
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

# Test 1: android-sdk compiles to a RUN of its setup script, with its args intact.
if echo "$DOCKERFILE" | grep -qE "RUN android-sdk--setup\.sh --cmdline-tools 11076708 --api 34 --build-tools 34\.0\.0" \
   && ! echo "$DOCKERFILE" | grep -q "Unknown setup script 'android-sdk'"; then
    print_test_result "true" "$0" "1" "setup android-sdk compiles to RUN android-sdk--setup.sh"
else
    print_test_result "false" "$0" "1" "setup android-sdk should compile to RUN android-sdk--setup.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# Test 2: the JDK must be installed first — sdkmanager is a Java program, so a
# reversed order fails the build with "sdkmanager needs a JDK on PATH".
JDK_LINE=$(echo "$DOCKERFILE" | grep -n "RUN jdk--setup\.sh" | head -1 | cut -d: -f1)
SDK_LINE=$(echo "$DOCKERFILE" | grep -n "RUN android-sdk--setup\.sh" | head -1 | cut -d: -f1)
if [[ -n "$JDK_LINE" && -n "$SDK_LINE" && "$JDK_LINE" -lt "$SDK_LINE" ]]; then
    print_test_result "true" "$0" "2" "jdk--setup.sh precedes android-sdk--setup.sh"
else
    print_test_result "false" "$0" "2" "jdk--setup.sh should precede android-sdk--setup.sh"
    echo "  JDK_LINE=$JDK_LINE SDK_LINE=$SDK_LINE"
    FAILED=$((FAILED + 1))
fi

# The remaining tests build a real image, which needs android-sdk--setup.sh baked
# into the base image. Skip (reporting the emit results) when one isn't present.
use_local_base_image || exit $FAILED

# android-sdk--setup.sh gates itself on amd64 — Google publishes the cmdline-tools
# for linux x86_64 only, so on arm64 it warns and installs nothing by design. The
# tools these tests assert on are then legitimately absent, so skip rather than
# report a failure for a documented no-op.
SERVER_ARCH="$(docker_server_arch)"
if [[ "$SERVER_ARCH" != "amd64" ]]; then
    echo "SKIP: Android SDK is published for linux x86_64 only; docker builds for '${SERVER_ARCH}' here." >&2
    exit $FAILED
fi

# Test 3: the SDK tools resolve in a NON-LOGIN shell. This is the regression that
# matters: /etc/profile.d is not sourced by `booth -- cmd`, so a setup that wires
# PATH only through profile.d passes interactively and fails in every script.
ACTUAL=$(run_coding_booth --silence-build -- 'command -v aapt2 && command -v adb && command -v sdkmanager' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -q "aapt2" && echo "$ACTUAL" | grep -q "adb" && echo "$ACTUAL" | grep -q "sdkmanager"; then
    print_test_result "true" "$0" "3" "SDK tools are on PATH in a non-login shell"
else
    print_test_result "false" "$0" "3" "SDK tools should be on PATH in a non-login shell"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: the binaries run. A broken shim or an unreadable SDK tree would still
# satisfy `command -v`.
#
# aapt2 prints its version on stderr, not stdout, so the streams have to be
# folded together here — dropping stderr makes this look like a silent failure.
ACTUAL=$(run_coding_booth --silence-build -- 'aapt2 version 2>&1' 2>/dev/null | grep -m1 .) || ACTUAL=""
if echo "$ACTUAL" | grep -qi "Android Asset Packaging Tool"; then
    print_test_result "true" "$0" "4" "aapt2 executes and reports its version"
else
    print_test_result "false" "$0" "4" "aapt2 should execute and report its version"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: the platform jar is installed AND readable by coder. The SDK is
# installed by root; without the chmod in the setup the tree is unreadable and
# every build fails with a confusing "file not found".
ACTUAL=$(run_coding_booth --silence-build -- 'test -r /opt/android-sdk/platforms/android-34/android.jar && echo READABLE' 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "READABLE" ]]; then
    print_test_result "true" "$0" "5" "android.jar for API 34 is readable by the booth user"
else
    print_test_result "false" "$0" "5" "android.jar for API 34 should be readable by the booth user"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
