#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# run_test_script (run-test-script--source.sh) is what the suite runners call
# each test through. On macOS's bash 3.2 a test that dies on an unbound variable
# under `set -u` exits 0 when it has a `trap … EXIT`, so the runner counted the
# crash as a pass; run_test_script reads bash's message off stderr and fails it.
#
# Each case is a tiny script written to a temp dir and run through the helper.
# On bash 4+ the masked case already exits 1 on its own, so there it checks the
# status is kept rather than that the guard fired — the same outcome a runner
# depends on either way.
#
# It lives with the setups tests because they are the host-side suite that
# needs no container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh
source ../run-test-script--source.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
N=0
check() {  # check <ok:true|false> <description>
    N=$((N + 1))
    print_test_result "$1" "$0" "$N" "$2"
    [[ "$1" == "true" ]] || FAILED=$((FAILED + 1))
}

# write <name> <body...>: an executable test-like script, set -euo pipefail.
write() {
    local name="$1"; shift
    { echo '#!/bin/bash'; echo 'set -euo pipefail'; printf '%s\n' "$@"; } > "$WORK/$name"
    chmod +x "$WORK/$name"
}

# run <name>: run it through the helper; sets RC, OUT (stdout), ERR (stderr).
run() {
    RC=0
    OUT="$(cd "$WORK" && run_test_script "./$1" 2>"$WORK/err")" || RC=$?
    ERR="$(cat "$WORK/err")"
}

# 1. The masked case: an EXIT trap, then an unbound variable under set -u. (Not
#    the usual empty `"${a[@]}"`: bash 4.4+ no longer treats that as unbound, so
#    the script would genuinely pass there.)
write test--masked.sh 'trap "true" EXIT' 'echo "$nope"' 'echo "never reached"'
run test--masked.sh
[[ "$RC" -ne 0 ]] && check true "a test that dies on an unbound variable under an EXIT trap fails (rc=$RC)" \
                  || check false "a test that dies on an unbound variable under an EXIT trap should fail (rc=$RC)"
if (( BASH_VERSINFO[0] < 4 )); then
    [[ "$ERR" == *"died on an unbound variable and still exited 0"* ]] \
        && check true "…and the runner says why" \
        || check false "…and the runner should say why (stderr: $ERR)"
fi

# 2. The same thing from a harness file the test sources.
printf '%s\n' 'echo "$nope"' > "$WORK/lib--source.sh"
write test--masked-in-lib.sh 'trap "true" EXIT' 'source ./lib--source.sh'
run test--masked-in-lib.sh
[[ "$RC" -ne 0 ]] && check true "an unbound variable in a sourced *--source.sh fails the test too (rc=$RC)" \
                  || check false "an unbound variable in a sourced *--source.sh should fail the test (rc=$RC)"

# 3. A clean test passes, and its stdout reaches the caller untouched.
write test--clean.sh 'trap "true" EXIT' 'echo "result line"'
run test--clean.sh
[[ "$RC" -eq 0 && "$OUT" == "result line" ]] \
    && check true "a clean test passes with its stdout intact" \
    || check false "a clean test should pass with its stdout intact (rc=$RC, out='$OUT')"

# 4. A child script's own unbound-variable message is not the test's: tests
#    run setup scripts they expect to fail, and pass.
write child.sh 'echo "$nope"'
write test--child-fails.sh 'trap "true" EXIT' 'if ./child.sh; then exit 1; fi' 'echo "child failed, as expected"'
run test--child-fails.sh
[[ "$RC" -eq 0 && "$ERR" == *"child.sh: line"*"unbound variable"* ]] \
    && check true "a child's unbound-variable message on stderr does not fail the test" \
    || check false "a child's unbound-variable message should not fail the test (rc=$RC, stderr: $ERR)"

# 5. A real failure keeps its own status.
write test--exit3.sh 'trap "true" EXIT' 'echo "boom" >&2' 'exit 3'
run test--exit3.sh
[[ "$RC" -eq 3 && "$ERR" == *boom* ]] \
    && check true "a failing test keeps its exit status (3) and its stderr" \
    || check false "a failing test should keep its exit status and stderr (rc=$RC, stderr: $ERR)"

# 5b. Started through the interpreter, as the config runners do, the name
#     matched is the script's, not "bash".
RC=0
OUT="$(cd "$WORK" && run_test_script bash ./test--masked.sh 2>"$WORK/err")" || RC=$?
[[ "$RC" -ne 0 ]] && check true "\`run_test_script bash <file>\` fails the masked case too (rc=$RC)" \
                  || check false "\`run_test_script bash <file>\` should fail the masked case (rc=$RC)"
RC=0
OUT="$(cd "$WORK" && run_test_script bash ./test--clean.sh 2>"$WORK/err")" || RC=$?
[[ "$RC" -eq 0 && "$OUT" == "result line" ]] \
    && check true "\`run_test_script bash <file>\` passes a clean test with its stdout" \
    || check false "\`run_test_script bash <file>\` should pass a clean test (rc=$RC, out='$OUT')"

# 6. The caller's errexit is left as it was: off stays off.
write test--ok.sh 'true'
(
    set +e
    run_test_script "$WORK/test--ok.sh"
    [[ $- != *e* ]]
) && check true "the caller's set +e is not turned into set -e" \
  || check false "the caller's set +e should not be turned into set -e"

exit $FAILED
