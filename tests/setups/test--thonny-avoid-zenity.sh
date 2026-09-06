#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Apt Thonny is 4.0.1: File → Open uses zenity unless file.avoid_zenity is True.
# file.use_zenity is a later key and is ignored — that wrong key is what made
# Open a no-op over VNC (zenity exit 255). This test locks the 4.0.1 key.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/variants/base/setups/thonny--setup.sh"

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = "true" ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [ -n "$detail" ] && echo "$detail" | sed 's/^/          /'
        ALL_PASSED=false
    fi
}

if grep -q 'avoid_zenity = True' "$SETUP"; then
    check "thonny--setup.sh seeds file.avoid_zenity = True (Thonny 4.0.1)" "true"
else
    check "thonny--setup.sh seeds file.avoid_zenity = True (Thonny 4.0.1)" "false" \
        "missing avoid_zenity = True — 4.0.1 ignores file.use_zenity"
fi

if grep -q 'cp.set("file", "avoid_zenity", "True")' "$SETUP"; then
    check "wrapper Python sets file.avoid_zenity on every launch" "true"
else
    check "wrapper Python sets file.avoid_zenity on every launch" "false" \
        "wrapper must set avoid_zenity, not only use_zenity"
fi

# Run the wrapper's Python (extracted from the setup) against a throwaway HOME.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PY_BLOCK=$(python3 - "$SETUP" <<'PY'
from pathlib import Path
import re, sys
src = Path(sys.argv[1]).read_text()
m = re.search(r"python3 - <<'PY'\n(.*?)\nPY", src, re.S)
if not m:
    sys.exit("no wrapper python block")
print(m.group(1), end="")
PY
)
HOME="$TMP" python3 -c "$PY_BLOCK"
CONF="$TMP/.config/Thonny/configuration.ini"
if grep -q 'avoid_zenity = True' "$CONF"; then
    check "wrapper python writes avoid_zenity = True into the user ini" "true"
else
    check "wrapper python writes avoid_zenity = True into the user ini" "false" "$(cat "$CONF" 2>/dev/null || echo missing)"
fi

if [ "$ALL_PASSED" = "true" ]; then
    exit 0
else
    exit 1
fi
