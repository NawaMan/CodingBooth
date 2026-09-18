#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# One answer to "which booth does this test run?".
#
# A test has two candidates. The locally built CLI — what `build/cli-build.sh`
# leaves at the repo root — is the one a test almost always wants: it is the code
# under test, built from this checkout, this minute. The `booth` wrapper is the
# fallback, and it runs whatever release binary its lock file names, which is a
# different program with a different version.
#
# Every test used to pick between them itself, with a line like
#
#     if [ -x "$REPO_ROOT/codingbooth" ]; then BOOTH="$REPO_ROOT/codingbooth" ...
#
# and that line is wrong on Windows. cli-build.sh writes the host build to
# `codingbooth.exe` there; the extensionless `codingbooth` beside it is the Linux
# cross-build, which is not executable on the host. So the test fell through to
# the wrapper — silently, with nothing in the output to say the local build had
# been skipped. A whole suite could pass against a release binary while the
# change under test sat unbuilt in the tree, or, worse, pass against an *older*
# release: the wrapper's version pins the base image tag, so a 0.77.0 binary
# builds `FROM nawaman/codingbooth:base-0.77.0` no matter what version.txt says.
#
# Hence one resolver, in one file. It knows the platform's binary name, and a
# test that sources it cannot get that wrong by copying the old line.
#
# Usage, at the top of a test, after REPO_ROOT is known:
#
#     source "$REPO_ROOT/tests/booth-bin--source.sh"
#     BOOTH="$(resolve_booth_bin)"
#
# Both functions default to walking up from the *calling script's* directory, so
# neither takes an argument in the common case. Pass one to start somewhere else.
#
#   resolve_booth_bin      — the local build, else the nearest `booth` wrapper.
#                            What a test that just needs to run a booth wants.
#   find_local_booth_build — the local build or nothing (returns 1). For a caller
#                            that must have the real CLI, not a wrapper around a
#                            release: reading `version`, or a subcommand a given
#                            release may not have.
#
# The walk stops at the checkout root — the directory holding `.git` — and never
# climbs past it. A linked worktree lives *under* the main clone
# (worktree/<name>/), so without that stop a session with nothing built yet would
# silently run main's binary and test the wrong tree.
#
# The wrapper fallback is the nearest one walking up, which for an example test
# is that example's own `./booth` rather than the repo root's. They are the same
# program; the difference is the lock file beside it, and an example's lock is
# rewritten from version.txt by examples/update-booth.sh, where the root's is
# whatever was downloaded last.
# -----------------------------------------------------------------------------

# Directory of the script that called into this file, for the default walk-up
# start. Frame 0 is this helper, frame 1 the public function it was called from,
# so frame 2 is the test itself — with the nearer frames as the fallback for a
# caller that is not a script (an interactive shell, `bash -c`).
_booth_bin_caller_dir() {
    local caller="${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-$0}}"
    (cd "$(dirname "$caller")" 2>/dev/null && pwd) || pwd
}

# The locally built CLI, searching this directory and its ancestors.
# Echoes the path and returns 0; prints nothing and returns 1 when there is none.
find_local_booth_build() {
    local dir="${1:-$(_booth_bin_caller_dir)}"
    dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1

    local candidate parent
    # .exe first: on Windows both names exist, and only one of them runs here.
    # Elsewhere there is no .exe and the loop costs a failed test per level.
    while :; do
        for candidate in "$dir/codingbooth.exe" "$dir/codingbooth"; do
            # -f before -x: on a case-insensitive filesystem (macOS) the repo
            # directory CodingBooth/ itself answers to -x, being a directory.
            if [[ -f "$candidate" && -x "$candidate" ]]; then
                echo "$candidate"
                return 0
            fi
        done
        [[ -e "$dir/.git" ]] && break        # checkout root: do not escape it
        parent="$(dirname "$dir")"
        [[ "$parent" == "$dir" ]] && break   # at the root: dirname stops moving
        dir="$parent"
    done

    return 1
}

# The booth a test should run: the local build when there is one, otherwise the
# nearest `booth` wrapper. Echoes the path; with neither — the caller is not
# inside a CodingBooth checkout — it complains on stderr and returns 1.
resolve_booth_bin() {
    local start="${1:-$(_booth_bin_caller_dir)}"

    local found
    if found="$(find_local_booth_build "$start")"; then
        echo "$found"
        return 0
    fi

    local dir parent
    dir="$(cd "$start" 2>/dev/null && pwd)" || return 1
    while :; do
        if [[ -f "$dir/booth" && -x "$dir/booth" ]]; then
            echo "$dir/booth"
            return 0
        fi
        [[ -e "$dir/.git" ]] && break        # checkout root: do not escape it
        parent="$(dirname "$dir")"
        [[ "$parent" == "$dir" ]] && break   # at the root: dirname stops moving
        dir="$parent"
    done

    # Loud, because most callers assign this under `set -e`: without a message
    # the script would simply stop, with no line saying what was looked for.
    echo "ERROR: no codingbooth build and no booth wrapper found above $start" >&2
    return 1
}
