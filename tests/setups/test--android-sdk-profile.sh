#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: android-sdk--setup.sh renders its login profile
#
# The profile is written from an unquoted heredoc, so every `$` in it is expanded
# while the image builds, under `set -u`. A comment that mentioned
# $XDG_CONFIG_HOME unescaped failed every build that selected android-sdk:
#   android-sdk--setup.sh: line 122: XDG_CONFIG_HOME: unbound variable
# Running the whole setup means downloading the SDK, so the heredoc is extracted
# and rendered the same way the setup renders it, and the result is sourced.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/android-sdk--setup.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# From `cat >/etc/profile.d/63-cb-android-sdk--profile.sh <<EOF` to its EOF,
# written to a file of ours instead.
awk '/^cat >\/etc\/profile.d\/63-cb-android-sdk--profile.sh <<EOF$/{f=1; print "cat >\"$OUT\" <<EOF"; next}
     f && /^EOF$/{print; exit}
     f' "$SETUP_SCRIPT" > "$WORK/render.sh"
if ! grep -q '^EOF$' "$WORK/render.sh"; then
    echo "❌ Could not extract the 63-cb-android-sdk--profile.sh heredoc from $SETUP_SCRIPT"
    exit 1
fi

ALL_PASSED=true
TEST_NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    print_test_result "$ok" "$0" "$TEST_NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -8
        ALL_PASSED=false
    fi
}

# As at image build: set -u, root, and none of the desktop's variables.
PROFILE="$WORK/profile.sh"
RENDER_OUT=$(env -i PATH=/usr/bin:/bin SDK_ROOT=/opt/android-sdk OUT="$PROFILE" \
    bash -euo pipefail "$WORK/render.sh" 2>&1) && RC=0 || RC=$?
[[ "$RC" -eq 0 ]] \
    && check "true"  "the profile renders under set -u with nothing but SDK_ROOT set" \
    || check "false" "the profile renders under set -u with nothing but SDK_ROOT set" "rc=$RC"$'\n'"$RENDER_OUT"

bash -n "$PROFILE" 2>/dev/null \
    && check "true"  "the rendered profile is valid shell" \
    || check "false" "the rendered profile is valid shell" "$(cat "$PROFILE")"

grep -qF '$XDG_CONFIG_HOME' "$PROFILE" && grep -qF 'export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME/.android}"' "$PROFILE" \
    && check "true"  "variables meant for login time stay literal in the file" \
    || check "false" "variables meant for login time stay literal in the file" "$(cat "$PROFILE")"

GOT=$(env -i HOME=/home/someone PATH=/usr/bin:/bin bash -c ". '$PROFILE'; echo \"\$ANDROID_USER_HOME\"")
[[ "$GOT" == "/home/someone/.android" ]] \
    && check "true"  "sourced at login, it pins ANDROID_USER_HOME to ~/.android" \
    || check "false" "sourced at login, it pins ANDROID_USER_HOME to ~/.android" "got: $GOT"

GOT=$(env -i HOME=/home/someone ANDROID_USER_HOME=/data/android PATH=/usr/bin:/bin bash -c ". '$PROFILE'; echo \"\$ANDROID_USER_HOME\"")
[[ "$GOT" == "/data/android" ]] \
    && check "true"  "an ANDROID_USER_HOME the user set is kept" \
    || check "false" "an ANDROID_USER_HOME the user set is kept" "got: $GOT"

$ALL_PASSED || exit 1
