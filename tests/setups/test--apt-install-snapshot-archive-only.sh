#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: apt--install.sh pins Ubuntu's archive only, never a Launchpad PPA.
#
# apt maps PPAs to snapshot.ppa.launchpadcontent.net too, and a PPA's snapshot
# may not have the release yet on the pinned day: with APT_SNAPSHOT at
# 20261004T000000Z the Mozilla PPA has no `resolute`, so every install after
# `setup firefox` failed. Both apt-get calls must clear the two PPA mappings
# whenever --snapshot is passed, and pass neither when it is not.
# apt-get and dpkg are stubbed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APT_SCRIPT="$REPO_ROOT/variants/base/setups/apt--install.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
LOG="$STUB/apt-get.log"

cat > "$STUB/apt-get" << 'EOF'
#!/bin/bash
echo "apt-get $*" >> "${STUB_LOG:?}"
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

SNAP="20261004T000000Z"
CLEAR_LP="-o Acquire::Snapshots::URI::Host::ppa.launchpad.net="
CLEAR_LPC="-o Acquire::Snapshots::URI::Host::ppa.launchpadcontent.net="

# run <APT_SNAPSHOT> — prints "rc=<n>" then the script's output; apt-get calls land in $LOG.
run() {
    local rc=0 out
    : > "$LOG"
    out="$(PATH="$STUB:$PATH" STUB_LOG="$LOG" \
        APT_SNAPSHOT="$1" CB_IMAGE_APT_SNAPSHOT="" \
        SETUP_LIBS_DIR="$REPO_ROOT/variants/base/setups/libs" CB_RETRY_DELAY=0 \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$APT_SCRIPT" firefox-esr 2>&1)" || rc=$?
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
# calls_with <apt-get subcommand> <text> — how many of those calls carry the text.
calls_with() { grep "^apt-get $1 " "$LOG" | grep -cF -- "$2" || true; }

out="$(run "$SNAP")"
if grep -qF "rc=0" <<< "$out" \
    && [ "$(calls_with update "--snapshot $SNAP")" = 1 ] \
    && [ "$(calls_with update "$CLEAR_LP")" = 1 ] && [ "$(calls_with update "$CLEAR_LPC")" = 1 ] \
    && [ "$(calls_with install "--snapshot $SNAP")" = 1 ] \
    && [ "$(calls_with install "$CLEAR_LP")" = 1 ] && [ "$(calls_with install "$CLEAR_LPC")" = 1 ]; then
    check "a pinned update and install leave Launchpad PPAs live" true
else
    check "a pinned update and install leave Launchpad PPAs live" false "$out"$'\n'"$(cat "$LOG")"
fi

out="$(run "")"
if grep -qF "rc=0" <<< "$out" && ! grep -qF -- "--snapshot" "$LOG" \
    && ! grep -qF -- "Acquire::Snapshots" "$LOG"; then
    check "no pin passes neither --snapshot nor the PPA options" true
else
    check "no pin passes neither --snapshot nor the PPA options" false "$out"$'\n'"$(cat "$LOG")"
fi

out="$(STUB_ARCH=arm64 run "$SNAP")"
if grep -qF "rc=0" <<< "$out" && ! grep -qF -- "--snapshot" "$LOG" \
    && ! grep -qF -- "Acquire::Snapshots" "$LOG"; then
    check "on arm64, where the pin is dropped, neither is passed" true
else
    check "on arm64, where the pin is dropped, neither is passed" false "$out"$'\n'"$(cat "$LOG")"
fi

$ALL_PASSED
