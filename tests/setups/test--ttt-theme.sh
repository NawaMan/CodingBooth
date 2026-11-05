#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the start-up script ttt--setup.sh writes seeds TTT's theme and
# border style (zenith, rounded by default) where settings.json has none.
#
# Running the setup itself would download TTT, so the start-up is cut out of its
# heredoc and run as the user would, with HOME in a temp dir. That every booth
# gets it (base image) and that TTT reads it is the complex test's job
# (tests/complex/boothfile/test-boothfile-ttt).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed on this host, and the ttt theme start-up edits settings.json with it"
    exit 0
fi

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
mkdir -p "$WORK/home"

SETUP="$REPO_ROOT/variants/base/setups/ttt--setup.sh"
STARTUP="$WORK/74-cb-ttt-theme--startup.sh"
sed -n "/^cat > \"\$THEME_STARTUP\" <<'STARTUP'\$/,/^STARTUP\$/p" "$SETUP" | sed '1d;$d' > "$STARTUP"
CONF="$WORK/home/.config/ttt/settings.json"

# Each case starts from no inherited TTT_* values; a case passes its own.
run_startup() {
    env -u TTT_THEME -u TTT_BORDER_STYLE HOME="$WORK/home" "$@" bash "$STARTUP" 2>&1
}
look() {
    jq -c '[.theme, .editor.borderStyle]' "$CONF" 2>/dev/null || echo "<no settings.json>"
}

ALL_PASSED=true
TEST_NUM=0

pass_fail() {
    local ok="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc" "$@"
        ALL_PASSED=false
    fi
}

# 1. The setup writes the start-up (an empty cut means the heredoc moved).
if grep -q 'theme //= \$theme' "$STARTUP" && grep -q 'THEME_STARTUP=/usr/share/startup.d/74-cb-ttt-theme--startup.sh' "$SETUP"; then
    pass_fail true "ttt--setup.sh writes the theme start-up to startup.d"
else
    pass_fail false "ttt--setup.sh writes the theme start-up to startup.d" "startup=$(cat "$STARTUP")"
fi

# 2. No settings.json yet: one is made with zenith and rounded.
run_startup > /dev/null
if [ "$(look)" = '["zenith","rounded"]' ] && [ "$(jq -r '.version' "$CONF")" = "1" ]; then
    pass_fail true "a new booth starts on zenith with rounded borders"
else
    pass_fail false "a new booth starts on zenith with rounded borders" "settings=$(cat "$CONF" 2>&1)"
fi

# 3. A theme and border picked inside TTT stay, and other keys survive.
jq '.theme = "nord" | .editor.borderStyle = "sharp" | .lsp.servers.go.command = ["gopls"]' \
    "$CONF" > "$WORK/t" && mv "$WORK/t" "$CONF"
run_startup > /dev/null
if [ "$(look)" = '["nord","sharp"]' ] && [ "$(jq -c '.lsp.servers.go.command' "$CONF")" = '["gopls"]' ]; then
    pass_fail true "a theme, a border, and other keys already set are left alone"
else
    pass_fail false "a theme, a border, and other keys already set are left alone" "settings=$(jq -c . "$CONF")"
fi

# 4. ttt+theme's values (image env) are what a new booth gets.
rm -f "$CONF"
run_startup TTT_THEME=dracula TTT_BORDER_STYLE=double > /dev/null
if [ "$(look)" = '["dracula","double"]' ]; then
    pass_fail true "TTT_THEME and TTT_BORDER_STYLE pick the seeded values"
else
    pass_fail false "TTT_THEME and TTT_BORDER_STYLE pick the seeded values" "look=$(look)"
fi

# 5. An empty value leaves that key to TTT; both empty write nothing at all.
rm -f "$CONF"
run_startup TTT_THEME= > /dev/null
if [ "$(look)" = '[null,"rounded"]' ]; then
    pass_fail true "an empty TTT_THEME leaves the theme unset"
else
    pass_fail false "an empty TTT_THEME leaves the theme unset" "look=$(look)"
fi
rm -f "$CONF"
run_startup TTT_THEME= TTT_BORDER_STYLE= > /dev/null
if [ ! -e "$CONF" ]; then
    pass_fail true "both empty write no settings.json"
else
    pass_fail false "both empty write no settings.json" "settings=$(cat "$CONF")"
fi

# 6. A settings.json that is not JSON is left alone, with a warning, and the
#    start-up does not fail the container start.
printf '{not json' > "$CONF"
RC=0
OUT=$(run_startup) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(cat "$CONF")" = '{not json' ] && grep -q "is not JSON" <<< "$OUT"; then
    pass_fail true "a broken settings.json is kept, with a warning"
else
    pass_fail false "a broken settings.json is kept, with a warning" "rc=$RC out=$OUT"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
