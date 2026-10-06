#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: apt--install.sh explains a snapshot older than the image's own.
#
# A Boothfile pinned to an older snapshot than its image cannot always install:
# the image already has newer builds of some packages, and apt will not
# downgrade them. apt's error reads like a broken archive, so the script warns
# up front and, if the install fails, names the cause and the
# `booth config --apt-snapshot` fix. apt-get and dpkg are stubbed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APT_SCRIPT="$REPO_ROOT/variants/base/setups/apt--install.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT

cat > "$STUB/apt-get" << 'EOF'
#!/bin/bash
if [ "$1" = install ] && [ -n "${FAIL_INSTALL:-}" ]; then
    echo "libsqlite3-dev : Depends: libsqlite3-0 (= 3.45.1-1ubuntu2.7) but 3.45.1-1ubuntu2.8 is to be installed"
    echo "E: Unable to correct problems, you have held broken packages."
    exit 100
fi
exit 0
EOF
cat > "$STUB/dpkg" << 'EOF'
#!/bin/bash
echo "${STUB_ARCH:-amd64}"
EOF
cat > "$STUB/rm" << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB/apt-get" "$STUB/dpkg" "$STUB/rm"

IMAGE_SNAP="20261004T000000Z"
OLDER="20250101T000000Z"
NEWER="20261010T000000Z"

# run <APT_SNAPSHOT> [FAIL_INSTALL] — prints "rc=<n>" then the script's output.
run() {
    local rc=0 out
    out="$(PATH="$STUB:$PATH" \
        APT_SNAPSHOT="$1" CB_IMAGE_APT_SNAPSHOT="$IMAGE_SNAP" FAIL_INSTALL="${2:-}" \
        SETUP_LIBS_DIR="$REPO_ROOT/variants/base/setups/libs" CB_RETRY_DELAY=0 \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$APT_SCRIPT" libsqlite3-dev 2>&1)" || rc=$?
    echo "rc=${rc}"
    echo "$out"
}

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -30
        ALL_PASSED=false
    fi
}
has() { grep -qF -- "$2" <<< "$1"; }

out="$(run "$OLDER")"
has "$out" "rc=0" && has "$out" "⚠️  APT_SNAPSHOT=${OLDER} is older than this image's snapshot (${IMAGE_SNAP})." \
    && check "an older pin is warned about up front, and still installs when it can" true \
    || check "an older pin is warned about up front, and still installs when it can" false "$out"

out="$(run "$OLDER" 1)"
has "$out" "rc=1" \
    && has "$out" "❌ apt could not install from snapshot ${OLDER}: it is older than this" \
    && has "$out" "Fix: booth config --apt-snapshot ${IMAGE_SNAP}" \
    && has "$out" "or: booth config --apt-snapshot today" \
    && check "a failed install on an older pin names the cause and the fix" true \
    || check "a failed install on an older pin names the cause and the fix" false "$out"

out="$(run "$NEWER" 1)"
has "$out" "rc=1" && ! has "$out" "older than this image" \
    && check "a failed install on a newer pin is apt's own error, no snapshot advice" true \
    || check "a failed install on a newer pin is apt's own error, no snapshot advice" false "$out"

out="$(run "$IMAGE_SNAP")"
has "$out" "rc=0" && ! has "$out" "older than this image" \
    && check "the image's own snapshot is not older than itself" true \
    || check "the image's own snapshot is not older than itself" false "$out"

out="$(run "" 1)"
has "$out" "rc=1" && ! has "$out" "older than this image" \
    && check "no pin (no freeze) gets no snapshot advice" true \
    || check "no pin (no freeze) gets no snapshot advice" false "$out"

out="$(STUB_ARCH=arm64 run "$OLDER" 1)"
has "$out" "rc=1" && ! has "$out" "older than this image" \
    && check "on arm64, where the pin is dropped, no snapshot advice" true \
    || check "on arm64, where the pin is dropped, no snapshot advice" false "$out"

# An image built before CB_IMAGE_APT_SNAPSHOT existed: no basis to compare, so no claim.
out="$(IMAGE_SNAP="" run "$OLDER" 1)"
has "$out" "rc=1" && ! has "$out" "older than this image" \
    && check "an image without CB_IMAGE_APT_SNAPSHOT gets no snapshot advice" true \
    || check "an image without CB_IMAGE_APT_SNAPSHOT gets no snapshot advice" false "$out"

$ALL_PASSED
