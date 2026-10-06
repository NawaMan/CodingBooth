#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# build/apt-snapshot--source.sh picks the snapshot docker-build.sh builds images
# against — CB_APT_SNAPSHOT, then apt-snapshot.txt, then today — and refuses a
# value apt cannot use, saying what is wrong and how to fix it. No image built.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$REPO_ROOT/build/apt-snapshot--source.sh"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -20
        ALL_PASSED=false
    fi
}

# resolve [<pin-file-content>] — run resolve_apt_snapshot in $WORK with whatever
# CB_APT_SNAPSHOT the caller exported. Prints "<status>|<id>|<from>" then stderr.
resolve() {
    rm -f "$WORK/apt-snapshot.txt"
    [[ $# -gt 0 ]] && printf '%s\n' "$1" > "$WORK/apt-snapshot.txt"
    (
        cd "$WORK"
        source "$SOURCE"
        status=0
        resolve_apt_snapshot 2> "$WORK/err" || status=$?
        echo "${status}|${APT_SNAPSHOT:-}|${APT_SNAPSHOT_FROM:-}"
        cat "$WORK/err"
    )
}

today="$(date -u +%Y%m%d)T000000Z"
future="$(date -u -d '+2 days' +%Y%m%d 2>/dev/null || date -u -v+2d +%Y%m%d)T000000Z"

unset CB_APT_SNAPSHOT

out="$(resolve)"
check "no CB_APT_SNAPSHOT and no pin file: today" \
    "$([[ "$out" == "0|${today}|today" ]] && echo true || echo false)" "$out"

out="$(resolve 20250901T000000Z)"
check "no CB_APT_SNAPSHOT: the release's pin in apt-snapshot.txt" \
    "$([[ "$out" == "0|20250901T000000Z|apt-snapshot.txt" ]] && echo true || echo false)" "$out"

out="$(CB_APT_SNAPSHOT=20250101T000000Z resolve 20250901T000000Z)"
check "CB_APT_SNAPSHOT wins over the pin file" \
    "$([[ "$out" == "0|20250101T000000Z|CB_APT_SNAPSHOT" ]] && echo true || echo false)" "$out"

out="$(CB_APT_SNAPSHOT=today resolve 20250901T000000Z)"
check "CB_APT_SNAPSHOT=today is today's id" \
    "$([[ "$out" == "0|${today}|CB_APT_SNAPSHOT" ]] && echo true || echo false)" "$out"

# expect_refused <desc> <reason> <fix> — the last resolve failed, naming both.
expect_refused() {
    local desc="$1" reason="$2" fix="$3"
    [[ "$out" == 1\|* && "$out" == *"$reason"* && "$out" == *"$fix"* ]] \
        && check "$desc" true || check "$desc" false "$out"
}

out="$(CB_APT_SNAPSHOT=2026-01-01 resolve)"
expect_refused "a malformed CB_APT_SNAPSHOT is refused with the format" \
    '❌ CB_APT_SNAPSHOT: "2026-01-01" is not a snapshot id — the format is YYYYMMDDTHHMMSSZ' "Unset CB_APT_SNAPSHOT"

out="$(CB_APT_SNAPSHOT=20260230T000000Z resolve)"
expect_refused "a day that does not exist is refused" '"20260230T000000Z" is not a real date and time' "Unset CB_APT_SNAPSHOT"

out="$(CB_APT_SNAPSHOT=20220101T000000Z resolve)"
expect_refused "a snapshot before Ubuntu's first is refused" "is before 20230301T000000Z" "Unset CB_APT_SNAPSHOT"

out="$(CB_APT_SNAPSHOT=$future resolve)"
expect_refused "a future snapshot is refused" "is in the future" "Unset CB_APT_SNAPSHOT"

out="$(CB_APT_SNAPSHOT=none resolve)"
expect_refused "CB_APT_SNAPSHOT=none is refused: images are always pinned" "images are always built against a snapshot" "Unset CB_APT_SNAPSHOT"

out="$(resolve garbage)"
expect_refused "a broken pin file is refused, with how to restore it" \
    '❌ apt-snapshot.txt: "garbage" is not a snapshot id' 'git checkout -- apt-snapshot.txt'

# The repo's own pin must always pass its own check.
out="$(cp "$REPO_ROOT/apt-snapshot.txt" "$WORK/pin" && resolve "$(cat "$WORK/pin")")"
check "the committed apt-snapshot.txt is a valid pin" \
    "$([[ "$out" == 0\|*\|apt-snapshot.txt ]] && echo true || echo false)" "$out"

$ALL_PASSED
