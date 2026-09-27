#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the web console builds no root-absolute URLs
#
# A second console (start-webconsole) can be opened through another page's
# proxy — code-server's Web Preview serves it under /proxy/11111/. Every URL the
# console page builds must stay under that path: an absolute "/s1/" lands on the
# other page's server instead (code-server, or a 404), which is how the panes
# came up blank. The same holds for the login page, the shared overlay and the
# readiness script, which the variant wrappers also load at "/booth" — relative
# URLs resolve exactly as before there.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE="$REPO_ROOT/variants/base"

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -8
        ALL_PASSED=false
    fi
}

# A path of the console's own, opening a string, attribute or url(): "/s1/",
# '/login', url(/booth-assets/...), "/booth". Comments are skipped.
ABSOLUTE="[\"'\`(]/(s[1-4]/|booth-messages|booth-assets|proxy/|__booth|login|booth[\"'\`])"

for f in web-ttyd-split/index.html web-ttyd-split/login.html \
         setups/booth-message-overlay.html setups/booth-ready.js; do
    hits=$(grep -nE "$ABSOLUTE" "$BASE/$f" | grep -vE '^[0-9]+:\s*(//|\*|<!--)' || true)
    check "$f builds no root-absolute console URL" \
        "$([[ -z "$hits" ]] && echo true || echo false)" "$hits"
done

# The pane pages live one level down (s1/..s4/), so the fonts nginx injects into
# them point one level up.
TEMPLATE="$BASE/web-ttyd-split/nginx.conf.template"
check "pane font links point one level up, not to the root" \
    "$(grep -q '"\.\./booth-assets/' "$TEMPLATE" && ! grep -qE "(href=\"|url\()/booth-assets/" "$TEMPLATE" && echo true || echo false)"

# A pane's address is read back with the console's own base taken off, so the
# /proxy/<port>/ it sits under is not mistaken for the tab's own port.
check "pane addresses are matched after the console base is removed" \
    "$(grep -qF 'consolePath(loc.pathname).match(' "$BASE/web-ttyd-split/index.html" && echo true || echo false)"

# An expired pane takes over the console, never the top window, which inside
# Web Preview is code-server itself.
check "login escapes a pane into the console, not window.top" \
    "$(! grep -qF 'window.top.location' "$BASE/web-ttyd-split/login.html" \
        && grep -qF 'window.parent.location = window.location.href' "$BASE/web-ttyd-split/login.html" \
        && echo true || echo false)"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
