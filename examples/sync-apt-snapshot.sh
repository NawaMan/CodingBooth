#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Move every example workspace's apt snapshot up to the release's.
#
# An example pinned to an older snapshot than the images it builds on can fail to
# install packages that need an exact version of one the image already has newer —
# apt will not downgrade. The images are built at apt-snapshot.txt, and a new booth
# is frozen to it too (build/cli-build.sh stamps it into the CLI), so the examples
# follow it as well: one date for all three.
#
# Bumps go through `booth config --apt-snapshot`, never sed, so each example's
# .booth/.generated fingerprint stays valid. Only examples pinned OLDER than the
# target move; a newer pin, or an empty one (no freeze), is left alone.
#
# Usage: examples/sync-apt-snapshot.sh [--check] [--to <id>] [example ...]
#   example   workspace folder name(s) under examples/workspaces/ (default: all)
#   --to      the snapshot to move to (default: apt-snapshot.txt)
#   --check   only list the examples that are behind; exit 1 when there are any

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACES_DIR="${EXAMPLES_WORKSPACES_DIR:-$SCRIPT_DIR/workspaces}"
CODINGBOOTH="${CODINGBOOTH:-$REPO_DIR/codingbooth}"

# An --rc version has no release catalog to fetch, so use the repo's templates.
export CB_TEMPLATES_PATH="${CB_TEMPLATES_PATH:-$REPO_DIR/templates}"
# The snapshot is chosen here, explicitly; an inherited override must not leak in.
unset CB_APT_SNAPSHOT

CHECK=false
TARGET=""
EXAMPLES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)   CHECK=true ;;
        --to)      TARGET="${2:-}"; shift ;;
        -h|--help) sed -n '6,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "Unknown option: $1" >&2; exit 2 ;;
        *)         EXAMPLES+=("${1%/}") ;;
    esac
    shift
done

if [[ -z "$TARGET" ]]; then
    TARGET="$(tr -d ' \t\r\n' < "$REPO_DIR/apt-snapshot.txt" 2>/dev/null)"
fi
if [[ ! "$TARGET" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
    echo "Error: no snapshot id to move to (got '${TARGET}'); pass --to <id> or fix apt-snapshot.txt." >&2
    exit 2
fi

if ! $CHECK && [[ ! -x "$CODINGBOOTH" ]]; then
    echo "Error: $CODINGBOOTH not found -- run ./build/cli-build.sh first." >&2
    exit 2
fi

if [[ ${#EXAMPLES[@]} -eq 0 ]]; then
    for dir in "$WORKSPACES_DIR"/*/; do
        dir="${dir%/}"
        [[ -f "$dir/.booth/Boothfile" ]] && EXAMPLES+=("$(basename "$dir")")
    done
fi

behind=0 failed=0
for name in "${EXAMPLES[@]}"; do
    ws="$WORKSPACES_DIR/$name"
    pinned="$(grep -m1 -o '^env APT_SNAPSHOT=[0-9TZ]*' "$ws/.booth/Boothfile" 2>/dev/null | cut -d= -f2)"
    [[ -n "$pinned" && "$pinned" < "$TARGET" ]] || continue
    behind=$((behind + 1))

    if $CHECK; then
        echo "$name  $pinned < $TARGET"
        continue
    fi

    # From inside the workspace: the path given to booth config lands in the header.
    if out="$(cd "$ws" && "$CODINGBOOTH" config --no-tui --overwrite --apt-snapshot "$TARGET" </dev/null 2>&1)"; then
        rm -f "$ws/.booth"/*.bak
        echo "$name  $pinned -> $TARGET"
    else
        failed=$((failed + 1))
        echo "$name  FAILED"
        sed 's/^/    /' <<< "$out"
    fi
done

if $CHECK; then
    echo "${behind} example(s) behind ${TARGET}"
    (( behind == 0 ))
else
    echo "${behind} example(s) moved to ${TARGET}, ${failed} failed"
    (( failed == 0 ))
fi
