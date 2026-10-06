#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a booth that can reach the host as root (--dind, --privileged run-args)
# is not started without consent.
#
# With no terminal to ask on, booth must refuse before building or starting
# anything, and name the flag that would allow it. A config.toml cannot grant
# that consent itself; only the command-line flag can.
#
# Runs in a session of its own so there is no controlling terminal: otherwise
# booth would prompt on /dev/tty and the test would hang. See no_tty_run in
# tests/common--source.sh for how that is done without setsid, which macOS does
# not have. The unit tests in pkg/booth/host_escape_consent_test.go cover the
# prompt answers and which run-args count.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh
sidecars_supported --dind || exit 0

no_tty_supported || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTH="$(find_local_booth_build "$SCRIPT_DIR")"

TEST_DIR=$(mktemp -d)
NAME="cb-test029-consent-$$"
trap 'rm -rf "$TEST_DIR"; docker rm -f "$NAME" "$NAME-dind" >/dev/null 2>&1 || true' EXIT
mkdir -p "$TEST_DIR/.booth"

FAILED=0

# no_tty_booth ARGS... : run the CLI with no controlling terminal and stdin closed.
no_tty_booth() {
    (cd "$TEST_DIR" && no_tty_run "$BOOTH" --name "$NAME" --variant base "$@" </dev/null 2>&1)
}

check() { # check <ok> <description> <output>
    if [[ "$1" == "true" ]]; then
        print_test_result "true" "$0" "029" "$2"
    else
        print_test_result "false" "$0" "029" "$2"
        echo "  Output: $3"
        FAILED=$((FAILED + 1))
    fi
}

no_container() {
    [[ -z "$(docker ps -aq --filter "name=^${NAME}")" ]]
}

# 1. --dind with no terminal is refused, names --dind-allowed, and starts nothing.
STATUS=0
OUTPUT=$(no_tty_booth --dind -- echo CB_BOOTH_STARTED) || STATUS=$?
ok=false
if [[ $STATUS -ne 0 ]] && grep -q -- "--dind-allowed" <<<"$OUTPUT" \
   && ! grep -q CB_BOOTH_STARTED <<<"$OUTPUT" && no_container; then ok=true; fi
check "$ok" "--dind with no terminal is refused before anything starts" "$OUTPUT"

# 2. --privileged in config.toml run-args is refused the same way.
cat > "$TEST_DIR/.booth/config.toml" <<'TOML'
run-args = ["--privileged"]
TOML
STATUS=0
OUTPUT=$(no_tty_booth -- echo CB_BOOTH_STARTED) || STATUS=$?
ok=false
if [[ $STATUS -ne 0 ]] && grep -q -- "--privileged-allowed" <<<"$OUTPUT" \
   && ! grep -q CB_BOOTH_STARTED <<<"$OUTPUT" && no_container; then ok=true; fi
check "$ok" "--privileged run-args with no terminal are refused" "$OUTPUT"

# 3. config.toml cannot pre-approve itself.
cat > "$TEST_DIR/.booth/config.toml" <<'TOML'
dind = true
dind-allowed = true
privileged-allowed = true
TOML
STATUS=0
OUTPUT=$(no_tty_booth -- echo CB_BOOTH_STARTED) || STATUS=$?
ok=false
if [[ $STATUS -ne 0 ]] && grep -q -- "--dind-allowed" <<<"$OUTPUT" \
   && ! grep -q CB_BOOTH_STARTED <<<"$OUTPUT" && no_container; then ok=true; fi
check "$ok" "config.toml cannot grant consent to itself" "$OUTPUT"

# 4. The command-line flag does allow it: the booth starts and runs the command, and the warning
#    is still printed (the flag skips the question, not the warning).
cat > "$TEST_DIR/.booth/config.toml" <<'TOML'
run-args = ["--privileged"]
TOML
OUTPUT=$(no_tty_booth --silence-build --privileged-allowed -- echo CB_BOOTH_STARTED) || true
ok=false
if grep -q CB_BOOTH_STARTED <<<"$OUTPUT" && grep -q "BOOTH_SECURITY.md#kernel-access" <<<"$OUTPUT" \
   && grep -q "Allowed by --privileged-allowed" <<<"$OUTPUT"; then ok=true; fi
check "$ok" "--privileged-allowed starts the booth without asking, and still warns" "$OUTPUT"

# 5-7. Starting the booth again (exec --run on a stopped booth, booth start) prints the same warning from
#      the container's cb.security-warning label, without asking. Attaching to a running booth does
#      not. The warning goes to stderr, so exec's stdout stays clean.
docker rm -f "$NAME" >/dev/null 2>&1 || true
no_tty_booth --silence-build --daemon --keep-alive --privileged-allowed >/dev/null || true

ERR="$TEST_DIR/stderr"
booth_cmd() { # booth_cmd ARGS... : a lifecycle command with no terminal; stderr to $ERR
    (cd "$TEST_DIR" && no_tty_run "$BOOTH" "$@" </dev/null 2>"$ERR")
}

OUTPUT=$(booth_cmd exec --name "$NAME" -- echo CB_EXEC_OK) || true
ok=false
if [[ "$OUTPUT" == "CB_EXEC_OK" ]] && ! grep -q "reach the host" "$ERR"; then ok=true; fi
check "$ok" "exec on a running booth does not repeat the warning" "$OUTPUT / $(cat "$ERR")"

docker stop -t 2 "$NAME" >/dev/null 2>&1 || true
OUTPUT=$(booth_cmd exec --run --name "$NAME" -- echo CB_EXEC_OK) || true
ok=false
if [[ "$OUTPUT" == "CB_EXEC_OK" ]] && grep -q "  - --privileged" "$ERR" \
   && grep -q "This booth was created with these settings." "$ERR"; then ok=true; fi
check "$ok" "exec that starts a stopped booth warns on stderr, stdout stays clean" "$OUTPUT / $(cat "$ERR")"

docker stop -t 2 "$NAME" >/dev/null 2>&1 || true
booth_cmd start --name "$NAME" -d >/dev/null || true
ok=false
if grep -q "  - --privileged" "$ERR" && grep -q "This booth was created with these settings." "$ERR"; then ok=true; fi
check "$ok" "booth start warns again" "$(cat "$ERR")"

exit $FAILED
