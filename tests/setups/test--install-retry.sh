#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: cb_retry — retrying a package install past a transient registry error
#
# Every *--install.sh reaches a package registry mid-build, and registries have bad
# minutes. A Microsoft Marketplace 503 failed five consecutive image builds of
# tests/complex/test-boothfile-code-extension while the Open VSX half of the same
# run succeeded every time; `go install` had already needed a retry of its own
# because proxy.golang.org resets connections. Most package managers have no retry
# flag, so libs/retry-source.sh supplies one and the install scripts route through
# it.
#
# What has to stay true, and is asserted here:
#   1-6.   cb_retry retries a transient failure, gives up after a bounded number of
#          attempts, and preserves the command's own exit status.
#   7-10.  It does NOT retry a rejected package. Retrying a name that will read the
#          same on every attempt only makes each typo cost the full backoff, and
#          several install scripts promise a fast hard error on a bad id.
#   11-14. The wiring holds end to end, for both invocation shapes in the catalog:
#          a package manager called directly (npm) and one called through sudo
#          (bun). A 503 on the first call is retried and the install then succeeds.
#   15.    Every *--install.sh routes through cb_retry. This is the guard that
#          matters over time: a newly added install script picks the assertion up
#          automatically, and skipping the retry has to be declared here to pass.
#
# Managers are stubbed by a recorder that can be told to fail the first N calls, so
# nothing real is installed and no test ever sleeps.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"
RETRY_LIB="$SETUPS_DIR/libs/retry-source.sh"

STUB=$(mktemp -d)
MARKER="$STUB/invoked.log"
STATE="$STUB/state"
mkdir -p "$STATE"
trap "rm -rf $STUB" EXIT

# Recorder for every command an install script might shell out to. It logs the
# call, then fails the first FAIL_TIMES invocations with FAIL_MSG on stderr —
# which is how a registry outage reaches these scripts.
STUBBED_COMMANDS=(
    apt-get brew bun cabal cargo code-server conan conda deno dotnet gem go
    luarocks mix npm pecl pip pip3 python python3 sudo uv yarn
)
for cmd in "${STUBBED_COMMANDS[@]}"; do
    cat > "$STUB/$cmd" << EOF
#!/bin/bash
echo "$cmd \$*" >> "$MARKER"
n=\$(cat "$STATE/$cmd.n" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$STATE/$cmd.n"
if [ "\$n" -le "\${FAIL_TIMES:-0}" ]; then
    echo "\${FAIL_MSG:-Error: Server returned 503}" >&2
    exit 1
fi
exit 0
EOF
    chmod +x "$STUB/$cmd"
done

ALL_PASSED=true
TEST_NUM=0

pass_fail() {  # pass_fail <ok> <desc> [detail...]
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

# ---- 1-10. cb_retry semantics, against the real lib ------------------------
# Driven through a helper script rather than sourced here, so the lib runs under
# the `set -Eeuo pipefail` + ERR trap the install scripts use — the combination
# that decides whether a retry loop is safe to drop into them at all.
cat > "$STUB/drive.sh" << 'DRIVE'
#!/bin/bash
set -Eeuo pipefail
trap 'echo "TRAP on line $LINENO"; exit 9' ERR
source "$RETRY_LIB"
CB_RETRY_DELAY=0
COUNT="$1"; MSG="$2"; FAILS="$3"; RC="$4"; BARE="${5:-no}"
: > "$COUNT"

# The failing command counts its own attempts by appending a line per call, and
# answers with MSG/RC until FAILS of them are spent.
run() {
    cb_retry bash -c '
        n=$(wc -l < "$1"); n=$((n + 1)); echo x >> "$1"
        if [ "$n" -le "$3" ]; then echo "$2" >&2; exit "$4"; fi
        echo "install ok"
    ' _ "$COUNT" "$MSG" "$FAILS" "$RC"
}

if [ "$BARE" = yes ]; then
    # As the install scripts call it: a bare statement, so a final failure trips
    # the caller's own ERR trap exactly as the unwrapped command used to.
    run
else
    rc=0; run || rc=$?
    echo "STATUS=$rc"
fi
DRIVE
chmod +x "$STUB/drive.sh"

# drive <fails> <message> [exit-code] [bare] -> sets OUT, ATTEMPTS, RC, STATUS
drive() {
    local fails="$1" msg="$2" rc_want="${3:-1}" bare="${4:-no}"
    RC=0
    OUT=$(RETRY_LIB="$RETRY_LIB" bash "$STUB/drive.sh" \
            "$STATE/count" "$msg" "$fails" "$rc_want" "$bare" 2>&1) || RC=$?
    ATTEMPTS=$(wc -l < "$STATE/count" | tr -d ' ')
    STATUS=$(echo "$OUT" | sed -n 's/^STATUS=//p')
}

TRANSIENT="Error while installing extensions: Server returned 503"

drive 1 "$TRANSIENT"
[[ "$STATUS" == "0" && "$ATTEMPTS" == "2" ]] \
    && pass_fail true "a transient 503 is retried and the install then succeeds" \
    || pass_fail false "a transient 503 should be retried and then succeed" "status=$STATUS attempts=$ATTEMPTS" "$OUT"

echo "$OUT" | grep -qF "retrying in" \
    && pass_fail true "the retry is announced in the build log" \
    || pass_fail false "the retry should be announced in the build log" "$OUT"

drive 2 "$TRANSIENT"
[[ "$STATUS" == "0" && "$ATTEMPTS" == "3" ]] \
    && pass_fail true "two transient failures still clear inside the attempt budget" \
    || pass_fail false "two transient failures should still clear" "status=$STATUS attempts=$ATTEMPTS" "$OUT"

# Bounded: a registry that never comes back must fail the build, not loop.
drive 99 "$TRANSIENT"
[[ "$STATUS" != "0" && "$ATTEMPTS" == "3" ]] \
    && pass_fail true "a registry that never recovers fails after 3 attempts" \
    || pass_fail false "a registry that never recovers should fail after 3 attempts" "status=$STATUS attempts=$ATTEMPTS" "$OUT"

# The command's own exit status survives, so a caller that switches on it still can.
drive 99 "$TRANSIENT" 7
[[ "$STATUS" == "7" ]] \
    && pass_fail true "the command's exit status is preserved through the retries" \
    || pass_fail false "the command's exit status should be preserved" "status=$STATUS (wanted 7)" "$OUT"

# Called bare, as every install script calls it, a final failure still trips the
# caller's `set -Eeuo pipefail` ERR trap — and reports the caller's own line, not
# one inside the lib. Dropping cb_retry in front of a command must not change how
# a build failure is reported.
drive 99 "$TRANSIENT" 1 yes
echo "$OUT" | grep -qE "TRAP on line (17|1[0-9]|2[0-9])" \
    && pass_fail true "a final failure still trips the caller's ERR trap" \
    || pass_fail false "a final failure should trip the caller's ERR trap" "$OUT"

# Each of these is a permanent answer: it reads the same on the second attempt, so
# retrying it only delays a build that is going to fail.
for msg in \
    "ERROR: Could not find a version that satisfies the requirement nosuchpkg" \
    "npm ERR! 404 Not Found - GET https://registry.npmjs.org/nosuchpkg" \
    "E: Unable to locate package nosuchpkg" \
    "error: could not find \`nosuchcrate\` in registry \`crates-io\`"
do
    drive 99 "$msg"
    [[ "$ATTEMPTS" == "1" ]] \
        && pass_fail true "not retried: ${msg:0:40}..." \
        || pass_fail false "should not be retried: ${msg:0:40}..." "attempts=$ATTEMPTS" "$OUT"
done

# ---- 11-14. The wiring, end to end, for both invocation shapes -------------
# run_install <script> <fail-times> <args...>
run_install() {
    local script="$1" fails="$2"; shift 2
    : > "$MARKER"; rm -f "$STATE"/*.n
    PATH="$STUB:$PATH" \
    SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
    CB_RETRY_DELAY=0 \
    FAIL_TIMES="$fails" \
    FAIL_MSG="${FAIL_MSG:-$TRANSIENT}" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$SETUPS_DIR/$script" "$@" 2>&1
}

# npm: the manager is invoked directly.
RC=0
OUT=$(run_install npm--install.sh 1 somepkg) || RC=$?
N=$(grep -c "^npm install -g somepkg" "$MARKER" || true)
[[ $RC -eq 0 && "$N" == "2" ]] \
    && pass_fail true "npm--install.sh retries a 503 and then installs" \
    || pass_fail false "npm--install.sh should retry a 503 and then install" "rc=$RC calls=$N" "$OUT"

RC=0
OUT=$(run_install npm--install.sh 0 somepkg) || RC=$?
N=$(grep -c "^npm install -g somepkg" "$MARKER" || true)
[[ $RC -eq 0 && "$N" == "1" ]] \
    && pass_fail true "npm--install.sh calls the manager once when nothing goes wrong" \
    || pass_fail false "npm--install.sh should call the manager once on a clean run" "rc=$RC calls=$N" "$OUT"

# bun: the manager is invoked through sudo, the catalog's other shape.
RC=0
OUT=$(run_install bun--install.sh 1 somepkg) || RC=$?
N=$(grep -c "^sudo -u coder bun add -g somepkg" "$MARKER" || true)
[[ $RC -eq 0 && "$N" == "2" ]] \
    && pass_fail true "bun--install.sh retries a 503 through sudo and then installs" \
    || pass_fail false "bun--install.sh should retry a 503 through sudo" "rc=$RC calls=$N" "$OUT"

# A rejected package is still a fast hard error, not three attempts of one.
RC=0
OUT=$(FAIL_MSG="npm ERR! 404 Not Found - GET https://registry.npmjs.org/nosuchpkg" \
      run_install npm--install.sh 99 nosuchpkg) || RC=$?
N=$(grep -c "^npm install -g nosuchpkg" "$MARKER" || true)
[[ $RC -ne 0 && "$N" == "1" ]] \
    && pass_fail true "npm--install.sh fails immediately on a rejected package" \
    || pass_fail false "npm--install.sh should fail immediately on a rejected package" "rc=$RC calls=$N" "$OUT"

# ---- 15. Every install script routes through cb_retry ----------------------
# Two scripts legitimately do not source the lib directly, and say why here rather
# than being quietly missed:
#   code-extension  gets cb_retry through libs/code-extension-source.sh, which it
#                   already sources for the shared extension-dir resolution.
#   go              carries its own retry loop, predating this lib: proxy.golang.org
#                   resets connections often enough that it needed one first.
#   jetbrains-plugin  downloads the plugin zip with curl, whose own `--retry 3
#                     --retry-delay 3 --retry-all-errors` is the right tool and is
#                     what every other download-based setup in the catalog uses.
EXEMPT=("code-extension" "go" "jetbrains-plugin")
MISSING=()
COVERED=0
for script in "$SETUPS_DIR"/*--install.sh; do
    mgr=$(basename "$script"); mgr="${mgr%--install.sh}"
    case " ${EXEMPT[*]} " in *" $mgr "*) continue ;; esac
    if grep -q "cb_retry " "$script"; then
        COVERED=$((COVERED + 1))
    else
        MISSING+=("$mgr")
    fi
done

[[ ${#MISSING[@]} -eq 0 ]] \
    && pass_fail true "all ${COVERED} install scripts route their install through cb_retry" \
    || pass_fail false "install scripts not routed through cb_retry: ${MISSING[*]}" \
        "Add cb_retry to each, or list it in EXEMPT above with the reason."

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
