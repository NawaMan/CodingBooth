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
# Runs under `setsid` so there is no controlling terminal: otherwise booth would
# prompt on /dev/tty and the test would hang. The unit tests in
# pkg/booth/host_escape_consent_test.go cover the prompt answers and which
# run-args count.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTH="$(find_local_booth_build "$SCRIPT_DIR")"

TEST_DIR=$(mktemp -d)
NAME="cb-test029-consent-$$"
trap 'rm -rf "$TEST_DIR"; docker rm -f "$NAME" "$NAME-dind" >/dev/null 2>&1 || true' EXIT
mkdir -p "$TEST_DIR/.booth"

FAILED=0

# no_tty_booth ARGS... : run the CLI with no controlling terminal and stdin closed.
no_tty_booth() {
    (cd "$TEST_DIR" && setsid -w "$BOOTH" --name "$NAME" --variant base "$@" </dev/null 2>&1)
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
if [[ $STATUS -ne 0 ]] && ! grep -q CB_BOOTH_STARTED <<<"$OUTPUT" && no_container; then ok=true; fi
check "$ok" "config.toml cannot grant consent to itself" "$OUTPUT"

# 4. The command-line flag does allow it: the booth starts and runs the command.
cat > "$TEST_DIR/.booth/config.toml" <<'TOML'
run-args = ["--privileged"]
TOML
OUTPUT=$(no_tty_booth --silence-build --privileged-allowed -- echo CB_BOOTH_STARTED) || true
ok=false
grep -q CB_BOOTH_STARTED <<<"$OUTPUT" && ok=true
check "$ok" "--privileged-allowed starts the booth without asking" "$OUTPUT"

exit $FAILED
