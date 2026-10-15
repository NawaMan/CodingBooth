#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: libs/prebuilt-source.sh — the CodingBoothPrebuilt download helper
#
# rust-nb-kernel, scratch and excalidraw install a prebuilt release asset and only
# compile when there is none. The helper decides which of the two happens, so the
# cases that matter are:
#
#   1. Asset names: "any" is <tool>-<version>; "native" adds <distro>-<arch> from
#      /etc/os-release and uname, matching what CodingBoothPrebuilt publishes.
#   2. A published asset that matches its .sha256 unpacks into the destination,
#      without the tarball's top folder.
#   3. No asset (a version that was never prebuilt) returns 1 and leaves the
#      destination alone — the caller builds from source.
#   4. A checksum mismatch is NOT a fallback: the setup exits, installing nothing.
#
# Hermetic: CB_PREBUILT_URL points at a fake release tree served as file://, so
# nothing reaches GitHub and no image is needed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/variants/base/setups/libs/prebuilt-source.sh"

ALL_PASSED=true
TEST_NUM=0

report() {  # report <ok> <desc> [detail-lines...]
    local ok="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        for line in "$@"; do echo "      $line"; done
        ALL_PASSED=false
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A fake release: tool "demo" version 1.0, arch-independent, with a good checksum,
# and version 2.0 whose .sha256 is wrong.
make_release() {  # make_release <version> <good|bad>
    local version="$1" sum="$2" name="demo-$1"
    mkdir -p "$TMP/stage/$name/sub" "$TMP/release/$name"
    echo "hello $version" > "$TMP/stage/$name/sub/file.txt"
    tar -czf "$TMP/release/$name/$name.tar.gz" -C "$TMP/stage" "$name"
    if [ "$sum" = good ]; then
        (cd "$TMP/release/$name" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
    else
        echo "0000000000000000000000000000000000000000000000000000000000000000  $name.tar.gz" \
            > "$TMP/release/$name/$name.tar.gz.sha256"
    fi
}
make_release 1.0 good
make_release 2.0 bad

export CB_PREBUILT_URL="file://$TMP/release"
# shellcheck source=/dev/null
source "$LIB"

# 1. Asset names
got="$(cb_prebuilt_asset demo 1.0 any)"
if [ "$got" = "demo-1.0" ]; then
    report true "any-arch asset name is <tool>-<version>"
else
    report false "any-arch asset name is <tool>-<version>" "got: $got"
fi

distro="$(. /etc/os-release && echo "${ID}${VERSION_ID}")"
got="$(cb_prebuilt_asset demo 1.0 native)"
if [[ "$got" =~ ^demo-1\.0-${distro//./\\.}-(x86_64|arm64)$ ]]; then
    report true "native asset name is <tool>-<version>-<distro>-<arch> ($got)"
else
    report false "native asset name is <tool>-<version>-<distro>-<arch>" "got: $got"
fi

# 2. Good asset installs, top folder stripped
if out="$(cb_prebuilt_install demo 1.0 any "$TMP/dest-ok" 2>&1)" \
   && [ "$(cat "$TMP/dest-ok/sub/file.txt" 2>/dev/null)" = "hello 1.0" ]; then
    report true "a published asset unpacks into the destination without its top folder"
else
    report false "a published asset unpacks into the destination without its top folder" "$out"
fi

# 3. Missing asset → status 1, destination untouched
status=0
out="$(cb_prebuilt_install demo 9.9 any "$TMP/dest-missing" 2>&1)" || status=$?
if [ "$status" = 1 ] && [ ! -e "$TMP/dest-missing" ]; then
    report true "no asset returns 1 and leaves the destination alone (caller builds from source)"
else
    report false "no asset returns 1 and leaves the destination alone" "status: $status" "$out"
fi

# 4. Checksum mismatch → the setup exits; run in a subshell since it calls exit
status=0
out="$( (cb_prebuilt_install demo 2.0 any "$TMP/dest-bad"; echo "CONTINUED") 2>&1)" || status=$?
if [ "$status" != 0 ] && [[ "$out" != *CONTINUED* ]] && [[ "$out" == *"does not match"* ]] \
   && [ ! -e "$TMP/dest-bad" ]; then
    report true "a checksum mismatch exits the setup and installs nothing"
else
    report false "a checksum mismatch exits the setup and installs nothing" "status: $status" "$out"
fi

if [ "$ALL_PASSED" = true ]; then
    exit 0
else
    exit 1
fi
