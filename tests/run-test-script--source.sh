#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# run_test_script <script> [args...] — run one test script for a suite runner,
# and fail it when bash 3.2 has turned a crash into a pass.
#
# On macOS's /bin/bash (3.2), a script under `set -u` that hits an unbound
# variable — `${a[@]}` of an empty array is the usual one — aborts, and if it
# has a `trap … EXIT`, exits with the trap's status instead: 0. `$?` inside the
# trap is already 0, so no trap can notice. ~190 tests here have such a trap,
# and on a Mac any of them could die halfway and be counted green
# (test--install-empty-args.sh did, on `declare -A`). bash 4+ exits 1, so Linux
# and CI never see it.
#
# What survives is bash's message on stderr: "<file>: line N: <name>: unbound
# variable". So stderr is passed through as usual and also copied, and an exit
# 0 that comes with such a message from the test itself, or from a *--source.sh
# harness file it sourced, is reported as the failure it was. Messages from
# anything else — a setup script the test runs and expects to fail — have that
# script's name on them and are left alone.
#
# stdout is untouched. stderr goes through a pipe, so the test sees a pipe, not
# a terminal, on fd 2; the copy is complete by the time it is checked, because
# the pipeline waits for tee.
run_test_script() {
    local script="$1"
    shift
    local name err rc errexit=""
    name="$(basename "$script")"
    err="$(mktemp)"

    # The caller's errexit is put back as it was, not switched on.
    [[ $- == *e* ]] && errexit=1
    set +e
    { "$script" "$@" 2>&1 1>&3 3>&- | tee "$err" >&2; } 3>&1
    rc=${PIPESTATUS[0]}
    [[ -n "$errexit" ]] && set -e

    if [[ "$rc" -eq 0 ]] \
       && grep -qE "(^|/)(${name//./\\.}|[^/: ]*--source\.sh): line [0-9]+: .*: unbound variable$" "$err"; then
        echo "❌ ${name} died on an unbound variable and still exited 0 — bash ${BASH_VERSION%%(*}'s EXIT trap replaced the error's status:" >&2
        grep -E ": line [0-9]+: .*: unbound variable$" "$err" | sed 's/^/     /' >&2
        rc=1
    fi
    rm -f "$err"
    return "$rc"
}
