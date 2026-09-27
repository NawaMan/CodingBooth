#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: show/hide button on password fields
#
# This is a static-wiring test (no container required). It asserts that both
# places a booth asks for a password carry an eye button that reveals what was
# typed, so a typo can be fixed in place:
#   - login.html:   the Console UI sign-in page of a password-protected booth
#   - overlay:      the `booth message send --type password` dialog
# For each: the button is type="button" (a click must not submit the form),
# toggles the input's type and aria-pressed, and the sign-in page masks the
# field again on submit so a password manager still sees a password input.
# Both pages' inline scripts must parse (node --check, when node exists).
#
# The behaviour itself was exercised in a real booth by driving both pages in
# headless Chrome: wrong password, reveal, fix, sign in; then a password prompt
# answered from the overlay with the edited value arriving on the host.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
LOGIN="$REPO_ROOT/variants/base/web-ttyd-split/login.html"
OVR="$REPO_ROOT/variants/base/setups/booth-message-overlay.html"

FAILED=0
NUM=0

expect_contains() {
    local file="$1" needle="$2" desc="$3"
    NUM=$((NUM + 1))
    if grep -qF -- "$needle" "$file"; then
        print_test_result "true" "$0" "$NUM" "$desc"
    else
        print_test_result "false" "$0" "$NUM" "$desc"
        echo "    file:   $file"
        echo "    needle: $needle"
        FAILED=$((FAILED + 1))
    fi
}

# -- Sign-in page -------------------------------------------------------------
expect_contains "$LOGIN" '<button type="button" class="reveal" id="reveal" aria-label="Show password" aria-pressed="false"' \
    "login: eye button is type=button, starts hidden"
expect_contains "$LOGIN" 'aria-controls="password"' \
    "login: eye button controls the password input"
expect_contains "$LOGIN" "password.type = shown ? 'text' : 'password';" \
    "login: toggle switches the input type"
expect_contains "$LOGIN" "reveal.setAttribute('aria-pressed', shown ? 'true' : 'false');" \
    "login: toggle updates aria-pressed"
expect_contains "$LOGIN" "setRevealed(password.type === 'password');" \
    "login: click flips the current state"
expect_contains "$LOGIN" "password.setSelectionRange(start, end);" \
    "login: caret is kept across the toggle"
expect_contains "$LOGIN" "#submit {" \
    "login: full-width style is scoped to Sign in, not every button"

# Masking again on submit has to happen inside the submit handler, before the
# request goes out.
NUM=$((NUM + 1))
if python3 - "$LOGIN" <<'PY'
import sys
src = open(sys.argv[1]).read()
h = src.index("form.addEventListener('submit'")
m = src.index("setRevealed(false);", h)
f = src.index("fetch(", h)
sys.exit(0 if m < f else 1)
PY
then
    print_test_result "true" "$0" "$NUM" "login: field is masked again on submit, before the request"
else
    print_test_result "false" "$0" "$NUM" "login: field is masked again on submit, before the request"
    FAILED=$((FAILED + 1))
fi

# -- Overlay password prompt --------------------------------------------------
expect_contains "$OVR" '<button type="button" class="msg-reveal" aria-label="Show password" aria-pressed="false"' \
    "overlay: eye button is type=button, starts hidden"
expect_contains "$OVR" "onclick=\"window._msgReveal(this)\">' + REVEAL_ICONS + '</button></span>'" \
    "overlay: eye button sits in the password prompt and calls _msgReveal"
expect_contains "$OVR" "window._msgReveal = function (btn) {" \
    "overlay: defines window._msgReveal"
expect_contains "$OVR" 'input.type = shown ? "text" : "password";' \
    "overlay: toggle switches the input type"
expect_contains "$OVR" 'btn.setAttribute("aria-pressed", shown ? "true" : "false");' \
    "overlay: toggle updates aria-pressed"

# -- Inline scripts parse -----------------------------------------------------
for f in "$LOGIN" "$OVR"; do
    NUM=$((NUM + 1))
    name="$(basename "$f")"
    if command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        JS="$(mktemp --suffix=.js)"
        python3 - "$f" "$JS" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
open(sys.argv[2], "w").write("\n;\n".join(re.findall(r"<script>(.*?)</script>", src, re.S)))
PY
        if node --check "$JS" 2>/dev/null; then
            print_test_result "true" "$0" "$NUM" "$name: inline scripts pass node --check"
        else
            print_test_result "false" "$0" "$NUM" "$name: inline scripts fail node --check"
            node --check "$JS" 2>&1 | sed 's/^/    /'
            FAILED=$((FAILED + 1))
        fi
        rm -f "$JS"
    else
        print_test_result "true" "$0" "$NUM" "$name: node or python3 missing, syntax check skipped"
    fi
done

exit $FAILED
