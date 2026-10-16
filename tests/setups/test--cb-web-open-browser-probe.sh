#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: how cb-web-open picks a browser
#
# cb-web-open is what every desktop web-service icon runs on click — JupyterLab,
# viewmd, and a project's own (data-example's "Sales Explorer"). It ends by
# exec-ing the first browser it finds, so the test it uses to decide "found" is
# the whole behaviour: there is no second chance after an exec.
#
# The bug this locks out: on arm64 Google publishes no Linux build of Chrome, so
# google-chrome--setup.sh installs a placeholder at /usr/local/bin/google-chrome
# that explains itself and exits 127. A `command -v google-chrome` test says yes
# — it is a real, executable file — and the exec that followed replaced the
# process with the stub. Firefox, installed and working two branches down, was
# never reached. Because a .desktop launcher is Terminal=false, the stub's
# stderr went nowhere: on every arm64 desktop booth, all three icons silently
# did nothing. (common--source.sh's own have_python3 documents the same shape of
# trap with the Windows App Execution Aliases.)
#
# Nothing here needs a container, an image, or root: cb-web-open is run directly
# with PATH pointing at stub browsers and CB_WEB_CONF_DIR at a throwaway
# descriptor, and the assertions are on which browser it chose and with which
# arguments. PATH is set to the stub directory *alone* — with START_CMD empty,
# cb-web-open reaches the browser dispatch using only bash builtins, so no real
# browser on the test host can be picked up by accident and change the answer.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CB_WEB_OPEN="$REPO_ROOT/variants/base/setups/cb-web-open"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

# A port nothing is listening on, so is_up() is false and the descriptor's empty
# START_CMD short-circuits the start-and-wait branch — this test is about the
# browser dispatch below it, not about starting services.
PORT="$(pick_free_port)"
URL="http://localhost:${PORT}/lab"

CONF_DIR="$WORK/conf"
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/notebook.conf" <<EOF
PORT_ENV=
PORT_DEFAULT=${PORT}
URL_PATH=/lab
TOKEN_ENV=
START_CMD=
EOF

BIN="$WORK/bin"
mkdir -p "$BIN"

# PATH below is the stub directory alone, so neither the stubs' shebang nor the
# cb-web-open invocation can rely on PATH to find an interpreter. Resolve bash
# once, here, and name it absolutely in both places.
BASH_BIN="$(command -v bash)"

# A browser that runs: answers --version, and otherwise reports how it was
# called so the assertions can name both the browser and its window flag.
make_working_browser() {
    local name="$1"
    cat > "$BIN/$name" <<EOF
#!${BASH_BIN}
if [ "\${1:-}" = "--version" ]; then echo "$name 1.2.3"; exit 0; fi
echo "CHOSE=$name ARGS=\$*"
EOF
    chmod +x "$BIN/$name"
}

# The real arm64 placeholder, reduced to what matters: it exists, it is
# executable, it fails whatever it is asked — including --version.
make_stub_browser() {
    local name="$1"
    cat > "$BIN/$name" <<EOF
#!${BASH_BIN}
echo "$name is not installed: Google publishes no linux/arm64 build of Chrome." >&2
exit 127
EOF
    chmod +x "$BIN/$name"
}

RUN_OUT=""
RUN_EXIT=0
run_web_open() {
    RUN_OUT=$(PATH="$BIN" CB_WEB_CONF_DIR="$CONF_DIR" \
        "$BASH_BIN" "$CB_WEB_OPEN" notebook 2>&1 </dev/null) \
        && RUN_EXIT=0 || RUN_EXIT=$?
}

ALL_PASSED=true
TEST_NUM=0

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TEST_NUM=$((TEST_NUM + 1))
    if grep -qF -- "$needle" <<<"$haystack"; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc (missing: '$needle')"
        echo "$haystack" | sed 's/^/      /' | head -5
        ALL_PASSED=false
    fi
}

# ---- arm64: a Chrome stub must not shadow a working Firefox -----------------
rm -f "$BIN"/*
make_stub_browser    google-chrome
make_working_browser firefox
run_web_open
assert_contains "a google-chrome that cannot run is skipped for Firefox" \
    "$RUN_OUT" "CHOSE=firefox"
assert_contains "Firefox is opened in its own window on the service's URL" \
    "$RUN_OUT" "ARGS=--new-window ${URL}"

# ---- amd64: a working Chrome is still preferred, in app mode ----------------
rm -f "$BIN"/*
make_working_browser google-chrome
make_working_browser firefox
run_web_open
assert_contains "a google-chrome that runs is preferred over Firefox" \
    "$RUN_OUT" "CHOSE=google-chrome"
assert_contains "Chrome is opened chromeless in app mode" \
    "$RUN_OUT" "ARGS=--app=${URL}"

# ---- Chromium is preferred over Firefox, and also probed --------------------
rm -f "$BIN"/*
make_stub_browser    google-chrome
make_working_browser chromium
make_working_browser firefox
run_web_open
assert_contains "Chromium takes the app-mode slot when Chrome cannot run" \
    "$RUN_OUT" "CHOSE=chromium"

rm -f "$BIN"/*
make_stub_browser    google-chrome
make_stub_browser    chromium
make_working_browser firefox
run_web_open
assert_contains "a chromium stub is skipped the same way Chrome's is" \
    "$RUN_OUT" "CHOSE=firefox"

# ---- nothing usable: fall through to xdg-open, not to a stub ----------------
rm -f "$BIN"/*
make_stub_browser    google-chrome
make_working_browser xdg-open
run_web_open
assert_contains "with no usable browser the xdg-open last resort is reached" \
    "$RUN_OUT" "CHOSE=xdg-open"
assert_contains "xdg-open is handed the plain URL" \
    "$RUN_OUT" "ARGS=${URL}"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
