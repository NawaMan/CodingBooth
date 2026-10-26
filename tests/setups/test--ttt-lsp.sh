#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the start-up script ttt-lsp--setup.sh writes adds TTT's lsp.servers
# entries for the servers on PATH, once each.
#
# The setup writes two root-owned files (the server table under /opt and the
# start-up under /usr/share/startup.d); a copy with those two paths moved into a
# temp dir runs the same code as the user would. Servers are stub executables on
# a PATH that holds nothing else of theirs, so "installed" is whatever the case
# puts there. What a real TTT then does with the entries is the complex test's job
# (tests/complex/boothfile/test-boothfile-ttt).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed on this host, and the ttt-lsp start-up edits settings.json with it"
    exit 0
fi
require_host_tools "ttt-lsp start-up" bash4

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
mkdir -p "$WORK/root" "$WORK/home" "$WORK/bin"
sed -e "s#/opt/codingbooth/ttt#$WORK/root/ttt#g" \
    -e "s#/usr/share/startup.d#$WORK/root/startup.d#g" \
    -e 's/^\[\[ \$EUID -eq 0 \]\] ||.*$/:/' \
    "$REPO_ROOT/variants/base/setups/ttt-lsp--setup.sh" > "$WORK/ttt-lsp--setup.sh"
bash "$WORK/ttt-lsp--setup.sh" > /dev/null

STARTUP="$WORK/root/startup.d/74-cb-ttt-lsp--startup.sh"
CONF="$WORK/home/.config/ttt/settings.json"

install_server() {
    local name
    for name in "$@"; do
        printf '#!/bin/sh\n' > "$WORK/bin/$name"
        chmod +x "$WORK/bin/$name"
    done
}
run_startup() {
    HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" bash "$STARTUP" 2>&1
}
servers() {
    jq -c '.lsp.servers // {} | keys' "$CONF" 2>/dev/null || echo "<no settings.json>"
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

# 1. Nothing installed: no settings.json is created.
run_startup > /dev/null
if [ ! -e "$CONF" ]; then
    pass_fail true "no servers on PATH writes no settings.json"
else
    pass_fail false "no servers on PATH writes no settings.json" "settings=$(cat "$CONF")"
fi

# 2. Installed servers get their entries, with the command TTT is to start.
install_server marksman zls
run_startup > /dev/null
if [ "$(servers)" = '["markdown","zig"]' ] \
   && [ "$(jq -c '.lsp.servers.markdown.command' "$CONF")" = '["marksman","server"]' ]; then
    pass_fail true "each server on PATH gets an entry, under TTT's language key"
else
    pass_fail false "each server on PATH gets an entry, under TTT's language key" "servers=$(servers)"
fi

# 3. An entry the user edited stays edited, one they deleted stays deleted, and
#    keys of their own survive.
jq '.lsp.servers.markdown.command = ["my-marksman"] | del(.lsp.servers.zig) | .theme = "nord"' \
    "$CONF" > "$WORK/t" && mv "$WORK/t" "$CONF"
run_startup > /dev/null
if [ "$(servers)" = '["markdown"]' ] \
   && [ "$(jq -c '.lsp.servers.markdown.command' "$CONF")" = '["my-marksman"]' ] \
   && [ "$(jq -r '.theme' "$CONF")" = "nord" ]; then
    pass_fail true "an edited entry, a deleted entry, and other keys are left as the user made them"
else
    pass_fail false "an edited entry, a deleted entry, and other keys are left as the user made them" \
        "settings=$(jq -c . "$CONF")"
fi

# 4. A server installed later is added on the next start.
install_server gopls
run_startup > /dev/null
if [ "$(servers)" = '["go","markdown"]' ]; then
    pass_fail true "a server installed later is added on the next start"
else
    pass_fail false "a server installed later is added on the next start" "servers=$(servers)"
fi

# 5. Python is pylsp, what the booth installs, not TTT's own pyright default.
install_server pylsp
run_startup > /dev/null
if [ "$(jq -c '.lsp.servers.python.command' "$CONF")" = '["pylsp"]' ]; then
    pass_fail true "python is wired to pylsp"
else
    pass_fail false "python is wired to pylsp" "python=$(jq -c '.lsp.servers.python' "$CONF")"
fi

# 6. A settings.json that is not JSON is left alone, with a warning, and the
#    start-up does not fail the container start.
printf '{not json' > "$CONF"
install_server taplo
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
