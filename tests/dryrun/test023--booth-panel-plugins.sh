#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: BoothPanel plugin registry wiring
#
# Asserts the static-wiring contract that lets setup scripts drop in extra
# lifecycle-panel items (buttons, chips, timers) without editing overlay.html.
#
#   - booth-message-overlay.html   — exposes window.BoothPanel with register /
#                                    unregister / confirm / showProgress /
#                                    showStopped / apiBase; sorts #bl-body by
#                                    data-priority; built-ins carry priorities.
#   - booth-message-wrapper--setup — creates /usr/local/share/booth-message-
#                                    wrapper/plugins/ and concatenates *.js
#                                    files into the served HTML after the
#                                    overlay runs.
#
# Behavioral end-to-end (plugin dropped in → button appears in correct
# position → click fires) is exercised manually.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SETUPS="$REPO_ROOT/variants/base/setups"

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

# -- 1-5: built-in items carry a data-priority ------------------------------
expect_contains "$OVR" 'id="bl-run-time" data-priority="10"' \
    "overlay: run-time has data-priority=10"
expect_contains "$OVR" 'id="bl-count-down" data-priority="20"' \
    "overlay: count-down has data-priority=20"
expect_contains "$OVR" 'id="bl-idle-chip" data-priority="50"' \
    "overlay: idle chip has data-priority=50"
expect_contains "$OVR" 'id="bl-restart-btn" data-priority="90"' \
    "overlay: restart button has data-priority=90"
expect_contains "$OVR" 'id="bl-shutdown-btn" data-priority="100"' \
    "overlay: shutdown button has data-priority=100"

# -- 6-10: BoothPanel public API surface ------------------------------------
expect_contains "$OVR" "window.BoothPanel = panelApi" \
    "overlay: window.BoothPanel is exposed"
expect_contains "$OVR" "register: function (def)" \
    "overlay: BoothPanel.register defined"
expect_contains "$OVR" "unregister: function (id)" \
    "overlay: BoothPanel.unregister defined"
expect_contains "$OVR" "confirm: function (opts)" \
    "overlay: BoothPanel.confirm defined (reuses built-in confirm DOM)"
expect_contains "$OVR" "showProgress: function (text)" \
    "overlay: BoothPanel.showProgress defined"

# -- 11-13: body-sort + pendingConfirm + ready event -------------------------
expect_contains "$OVR" "function sortBody()" \
    "overlay: sortBody() helper sorts #bl-body by data-priority"
expect_contains "$OVR" "pendingConfirm" \
    "overlay: confirmYes/confirmNo branch on pendingConfirm from plugins"
expect_contains "$OVR" 'booth-panel-ready' \
    "overlay: emits booth-panel-ready DOM event after init"

# -- 14-16: wrapper creates plugins dir + ships PLUGINS_HTML -----------------
expect_contains "$WRAP" 'mkdir -p "${WRAPPER_DIR}/plugins"' \
    "wrapper-setup: creates /usr/local/share/booth-message-wrapper/plugins/"
expect_contains "$WRAP" 'PLUGINS_HTML=""' \
    "wrapper-setup: builds PLUGINS_HTML from plugins/*.js"
expect_contains "$WRAP" '${PLUGINS_HTML}' \
    "wrapper-setup: envsubst allow-list includes \${PLUGINS_HTML}"

# -- 17: bash syntax of the updated wrapper setup ---------------------------
NUM=$((NUM + 1))
if bash -n "$WRAP" 2>/dev/null; then
    print_test_result "true" "$0" "$NUM" "$(basename "$WRAP"): bash -n passes"
else
    print_test_result "false" "$0" "$NUM" "$(basename "$WRAP"): bash -n failed"
    bash -n "$WRAP" 2>&1 | sed 's/^/    /'
    FAILED=$((FAILED + 1))
fi

exit $FAILED
