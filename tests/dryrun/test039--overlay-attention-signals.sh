#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: overlay attention signals (chime / tab title / desktop notification)
#
# This is a static-wiring test (no container required). It asserts that
# booth-message-overlay.html defines window.BoothAlert with the agreed
# signals, and that every message surface is hooked into it:
#   - BoothAlert: E5/A5 chime, per-booth notification tag, attended() gate,
#                 audio armed on gestures in the page and its iframes
#   - hooks:      toasts (title only), banners, dialogs, idle prompt
#                 (live countdown title, click focuses "I'm here"),
#                 session-countdown warnings, poll-driven cleanup
#   - Help:       Enable desktop notifications button
#   - the overlay's inline scripts parse (node --check, when node exists)
#
# The behaviour itself was exercised in a real booth by driving the page in
# headless Chrome; see docs/BOOTH_UI_OVERLAY.md#attention-signals.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
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

# -- BoothAlert module --------------------------------------------------------
expect_contains "$OVR" "window.BoothAlert = {" \
    "overlay: defines window.BoothAlert"
expect_contains "$OVR" 'document.visibilityState === "visible" && document.hasFocus()' \
    "overlay: stays quiet when the tab is visible and focused"
expect_contains "$OVR" "note(659.25, t);" \
    "overlay: chime first note is E5"
expect_contains "$OVR" "note(880, t + 0.16);" \
    "overlay: chime second note is A5, 0.16 s later"
expect_contains "$OVR" 'if (!ctx || ctx.state !== "running") return;' \
    "overlay: chime only plays on a running AudioContext"
expect_contains "$OVR" 'var TAG = "booth-" + location.host;' \
    "overlay: desktop notifications are tagged per booth"
expect_contains "$OVR" '["keydown", "mousedown", "touchstart"]' \
    "overlay: audio is armed on key, mouse and touch gestures"
expect_contains "$OVR" 'document.querySelectorAll("iframe")' \
    "overlay: gestures inside same-origin iframes also arm audio"
expect_contains "$OVR" "#bl-idle-chip, #bl-help-btn, #bl-toggle, #msg-overlay" \
    "overlay: permission is asked only on clicks in the booth's own UI"

# -- Hooks --------------------------------------------------------------------
expect_contains "$OVR" 'alertFor({ key: "msg:" + m.id, title: m.title, quiet: true });' \
    "overlay: toasts only mark the title"
expect_contains "$OVR" 'el.querySelector(".banner-close").focus();' \
    "overlay: banners alert, click focuses OK"
expect_contains "$OVR" "interactive.forEach(alertDialog);" \
    "overlay: dialogs alert after rendering"
expect_contains "$OVR" 'shutting down " + (s > 0 ? "in " + s + "s" : "now")' \
    "overlay: idle prompt puts the countdown in the tab title"
expect_contains "$OVR" "data-idle-here=" \
    "overlay: idle prompt's I'm here button is addressable"
expect_contains "$OVR" "[data-idle-here=" \
    "overlay: idle notification click focuses I'm here"
expect_contains "$OVR" 'key: "warn:" + id' \
    "overlay: session-countdown warnings alert"
expect_contains "$OVR" 'window.BoothAlert.sync("msg:", seenAlertKeys);' \
    "overlay: messages that go away clear their title and notification"
expect_contains "$OVR" 'id="bl-help-notify-btn"' \
    "overlay: Help has an Enable desktop notifications button"

# -- Inline scripts parse -----------------------------------------------------
NUM=$((NUM + 1))
if command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    JS="$(mktemp --suffix=.js)"
    python3 - "$OVR" "$JS" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
open(sys.argv[2], "w").write("\n;\n".join(re.findall(r"<script>(.*?)</script>", src, re.S)))
PY
    if node --check "$JS" 2>/dev/null; then
        print_test_result "true" "$0" "$NUM" "overlay: inline scripts pass node --check"
    else
        print_test_result "false" "$0" "$NUM" "overlay: inline scripts fail node --check"
        node --check "$JS" 2>&1 | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
    rm -f "$JS"
else
    print_test_result "true" "$0" "$NUM" "overlay: node or python3 missing, syntax check skipped"
fi

exit $FAILED
