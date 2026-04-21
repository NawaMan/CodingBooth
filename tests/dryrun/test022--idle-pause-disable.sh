#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: idle Pause/Disable wiring across monitor, API server, overlay, wrapper
#
# Terminology:
#   Pause    — time-boxed hold ({"seconds": N}); auto-resumes to normal after
#              the window elapses. State file: .idle-pause-until (epoch).
#   Disable  — indefinite hold; only cleared by /idle/resume or a restart.
#              State file: .idle-disabled.
#
# This is a static-wiring test (no container required). It asserts that the
# shipped shell/HTML files agree on the contract:
#   - booth-message-api-server   — four /idle/* routes + matching handlers
#   - booth--idle-monitor        — state-file paths, chunked sleep helpers,
#                                  idle-prompt message, semantic answer codes
#   - booth-message-overlay.html — chip DOM, idle overlay, /idle/* fetches
#   - booth-message-wrapper--*.sh — window.BOOTH_IDLE_TIME injection
#   - Bash syntax is valid for all modified scripts
#
# The behavioral flow (idle→prompt→pause→disable→resume→shutdown) still needs
# a running container and is exercised manually per docs/BOOTH_IDLE.md.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SETUPS="$REPO_ROOT/variants/base/setups"

API="$SETUPS/booth-message-api-server"
MON="$SETUPS/booth--idle-monitor"
OVR="$SETUPS/booth-message-overlay.html"
WRAP="$SETUPS/booth-message-wrapper--setup.sh"

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

# -- 1-4: API server routes --------------------------------------------------
expect_contains "$API" "/booth-messages/api/idle/state)" \
    "api-server: GET /idle/state route is registered"
expect_contains "$API" "/booth-messages/api/idle/pause)" \
    "api-server: POST /idle/pause (time-boxed) route is registered"
expect_contains "$API" "/booth-messages/api/idle/disable)" \
    "api-server: POST /idle/disable (indefinite) route is registered"
expect_contains "$API" "/booth-messages/api/idle/resume)" \
    "api-server: POST /idle/resume route is registered"

# -- 5-8: API server handlers ------------------------------------------------
expect_contains "$API" "handle_idle_state()" "api-server: handle_idle_state defined"
expect_contains "$API" "handle_idle_pause()" "api-server: handle_idle_pause defined"
expect_contains "$API" "handle_idle_disable()" "api-server: handle_idle_disable defined"
expect_contains "$API" "handle_idle_resume()" "api-server: handle_idle_resume defined"

# -- 9-10: API-side state-file writes match monitor's expectations -----------
expect_contains "$API" ".idle-disabled" \
    "api-server: writes .idle-disabled marker (indefinite)"
expect_contains "$API" ".idle-pause-until" \
    "api-server: writes .idle-pause-until marker (time-boxed)"

# -- 11: pause seconds is validated and capped ------------------------------
expect_contains "$API" "7-day maximum" \
    "api-server: /idle/pause rejects values over 7 days"

# -- 12: /idle/state response uses new field names ---------------------------
expect_contains "$API" 'pause_until\":' \
    "api-server: /idle/state returns pause_until field"
expect_contains "$API" 'disabled\":' \
    "api-server: /idle/state returns disabled field"

# -- 13-15: monitor state files and helpers ----------------------------------
expect_contains "$MON" 'DISABLE_FILE="$TMP_DIR/.idle-disabled"' \
    "monitor: declares DISABLE_FILE = .idle-disabled"
expect_contains "$MON" 'PAUSE_UNTIL_FILE="$TMP_DIR/.idle-pause-until"' \
    "monitor: declares PAUSE_UNTIL_FILE = .idle-pause-until"
expect_contains "$MON" "sleep_idle_window" \
    "monitor: uses chunked sleep_idle_window helper"

# -- 16: monitor prompts with the bespoke idle-prompt type -------------------
expect_contains "$MON" '"type": "idle-prompt"' \
    "monitor: prompt message uses idle-prompt type"

# -- 17-19: monitor parses semantic answer codes -----------------------------
expect_contains "$MON" 'ok|"I'"'"'m here")' \
    "monitor: handles \"ok\" / \"I'm here\" acknowledgement"
expect_contains "$MON" 'pause:*)' \
    "monitor: parses pause:<seconds> answers (incl. custom)"
expect_contains "$MON" 'disable)' \
    "monitor: handles disable answer"

# -- 20-21: overlay recognises the idle-prompt type + Disable button ---------
expect_contains "$OVR" '"idle-prompt"' \
    "overlay: renders idle-prompt message type"
expect_contains "$OVR" "Disable idle shutdown" \
    "overlay: renders \"Disable idle shutdown\" button"

# -- 22-27: overlay DOM + fetch wiring ---------------------------------------
expect_contains "$OVR" 'id="bl-idle-chip"' \
    "overlay: idle chip element is present in lifecycle panel"
expect_contains "$OVR" 'id="bl-idle-overlay"' \
    "overlay: idle control dialog overlay is present"
expect_contains "$OVR" "/idle/state" \
    "overlay: fetches /idle/state for chip rendering"
expect_contains "$OVR" "/idle/pause" \
    "overlay: posts to /idle/pause for time-boxed pause actions"
expect_contains "$OVR" "/idle/disable" \
    "overlay: posts to /idle/disable for disable action"
expect_contains "$OVR" "/idle/resume" \
    "overlay: posts to /idle/resume for resume action"

# -- 28-29: chip uses new state field names ---------------------------------
expect_contains "$OVR" "state.disabled" \
    "overlay: reads state.disabled from /idle/state response"
expect_contains "$OVR" "state.pause_until" \
    "overlay: reads state.pause_until from /idle/state response"

# -- 30: overlay reads BOOTH_IDLE_TIME from window ---------------------------
expect_contains "$OVR" "window.BOOTH_IDLE_TIME" \
    "overlay: reads window.BOOTH_IDLE_TIME to decide chip visibility"

# -- 31-33: wrapper setup injects idle globals into window -------------------
expect_contains "$WRAP" 'window.BOOTH_IDLE_TIME=' \
    "wrapper-setup: injects window.BOOTH_IDLE_TIME into wrapper HTML"
expect_contains "$WRAP" 'window.BOOTH_IDLE_SHUTDOWN_TIME=' \
    "wrapper-setup: injects window.BOOTH_IDLE_SHUTDOWN_TIME into wrapper HTML"
expect_contains "$WRAP" '${BOOTH_IDLE_TIME}' \
    "wrapper-setup: BOOTH_IDLE_TIME is listed in envsubst allow-list"

# -- 34-36: bash syntax of modified scripts ----------------------------------
for f in "$API" "$MON" "$WRAP"; do
    NUM=$((NUM + 1))
    if bash -n "$f" 2>/dev/null; then
        print_test_result "true" "$0" "$NUM" "$(basename "$f"): bash -n passes"
    else
        print_test_result "false" "$0" "$NUM" "$(basename "$f"): bash -n failed"
        bash -n "$f" 2>&1 | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
done

exit $FAILED
