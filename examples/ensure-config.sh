#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Check that `booth config` can be run on every example workspace -- that what it
# would generate does not collide with the .booth/Boothfile and .booth/config.toml
# already there.
#
# Read-only: each workspace gets `booth config --no-tui --dryrun` with no flags,
# which reloads the booth from its own header and passes through the same
# hand-written guard a real run does, but writes nothing and starts no container.
#
# Usage: examples/ensure-config.sh [--diff] [example ...]
#   example   workspace folder name(s) under examples/workspaces/ (default: all)
#   --diff    show the diff for every example that would change
#
# Verdicts:
#   OK         regenerates byte-for-byte what is on disk
#   READ-BACK  hand edits that booth config can reproduce; they would be kept
#   CHANGES    regenerates fine, but the output differs (the catalog moved on)
#   COLLISION  refused: hand-written files would be overwritten
#   ERROR      booth config failed for another reason
#
# Exits 1 when any example is COLLISION or ERROR.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACES_DIR="${EXAMPLES_WORKSPACES_DIR:-$SCRIPT_DIR/workspaces}"
CODINGBOOTH="${CODINGBOOTH:-$REPO_DIR/codingbooth}"

# An --rc version has no release catalog to fetch, so use the repo's templates.
export CB_TEMPLATES_PATH="${CB_TEMPLATES_PATH:-$REPO_DIR/templates}"

SHOW_DIFF=false
EXAMPLES=()
for arg in "$@"; do
    case "$arg" in
        --diff)    SHOW_DIFF=true ;;
        -h|--help) sed -n '6,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "Unknown option: $arg" >&2; exit 2 ;;
        *)         EXAMPLES+=("${arg%/}") ;;
    esac
done

if [[ ! -x "$CODINGBOOTH" ]]; then
    echo "Error: $CODINGBOOTH not found -- run ./build/cli-build.sh first." >&2
    exit 2
fi

if [[ ${#EXAMPLES[@]} -eq 0 ]]; then
    for dir in "$WORKSPACES_DIR"/*/; do
        dir="${dir%/}"
        [[ -d "$dir/.booth" ]] && EXAMPLES+=("$(basename "$dir")")
    done
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Print a file without its trailing blank lines; the dryrun ends each section
# with one more newline than the file on disk has.
trim_trailing_blank() {
    [[ -f "$1" ]] || return 0
    awk '{ line[NR] = $0 } NF { last = NR } END { for (i = 1; i <= last; i++) print line[i] }' "$1"
}

# Split the dryrun's stdout into the generated config.toml and Boothfile.
split_dryrun() {
    local out="$1" prefix="$2"
    awk -v toml="$prefix.config.toml" -v bf="$prefix.Boothfile" '
        /^=== config\.toml ===$/ { file = toml; next }
        /^=== Boothfile ===$/    { file = bf;   next }
        /^=== /                  { file = "";   next }
        file != ""               { print > file }
    ' "$out"
}

count_ok=0 count_readback=0 count_changes=0 count_collision=0 count_error=0
width=0
for name in "${EXAMPLES[@]}"; do
    (( ${#name} > width )) && width=${#name}
done

for name in "${EXAMPLES[@]}"; do
    ws="$WORKSPACES_DIR/$name"
    out="$TMP_DIR/$name.out"
    err="$TMP_DIR/$name.err"
    detail=""

    if [[ ! -d "$ws/.booth" ]]; then
        verdict=ERROR
        detail="no .booth/ in $ws"
    else
        # Run from inside the workspace: that is how the examples were generated.
        (cd "$ws" && "$CODINGBOOTH" config --no-tui --dryrun >"$out" 2>"$err" </dev/null)
        rc=$?

        if grep -q '^Refusing to overwrite hand-written files' "$err"; then
            verdict=COLLISION
            detail="hand-written: $(awk '/^Refusing/ { on = 1; next } on && /^$/ && seen { exit }
                                         on && /^  / { sub(/^ +/, ""); printf "%s%s", (seen ? ", " : ""), $0; seen = 1 }' "$err")"
        elif (( rc != 0 )); then
            verdict=ERROR
            reason="$(grep -v '^ ' "$err" | grep -v '^Warning: apt snapshot' | grep -m1 .)"
            detail="exit $rc: ${reason:-(no error output)}"
        else
            split_dryrun "$out" "$TMP_DIR/$name.gen"
            changed=()
            for file in config.toml Boothfile; do
                if ! diff -q <(trim_trailing_blank "$TMP_DIR/$name.gen.$file") \
                             <(trim_trailing_blank "$ws/.booth/$file") >/dev/null; then
                    changed+=("$file")
                fi
            done

            if grep -q 'the edits were read back' "$err"; then
                verdict=READ-BACK
                detail="$(grep -m1 'the edits were read back' "$err" | sed 's/^Note: //')"
            elif [[ ${#changed[@]} -gt 0 ]]; then
                verdict=CHANGES
                detail="would change: ${changed[*]}"
            else
                verdict=OK
            fi

            if $SHOW_DIFF && [[ ${#changed[@]} -gt 0 ]]; then
                for file in "${changed[@]}"; do
                    detail+=$'\n'"$(diff -u --label "on disk: $file" --label "generated: $file" \
                        <(trim_trailing_blank "$ws/.booth/$file") \
                        <(trim_trailing_blank "$TMP_DIR/$name.gen.$file") | sed 's/^/        /')"
                done
            fi
        fi
    fi

    case "$verdict" in
        OK)        count_ok=$((count_ok + 1)) ;;
        READ-BACK) count_readback=$((count_readback + 1)) ;;
        CHANGES)   count_changes=$((count_changes + 1)) ;;
        COLLISION) count_collision=$((count_collision + 1)) ;;
        ERROR)     count_error=$((count_error + 1)) ;;
    esac
    printf "%-*s  %-9s  %s\n" "$width" "$name" "$verdict" "$detail"
done

echo
echo "Total ${#EXAMPLES[@]}: OK $count_ok, READ-BACK $count_readback, CHANGES $count_changes, COLLISION $count_collision, ERROR $count_error"

(( count_collision + count_error == 0 ))
