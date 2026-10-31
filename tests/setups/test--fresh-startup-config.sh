#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the startup hook fresh--setup.sh writes seeds Fresh's config
#
# Fresh left the base image when TTT became the default editor, so the config
# defaults the base profile used to write moved into the hook the fresh setup
# installs. Runs that hook, taken from the real setup script, with a scratch
# HOME, and asserts:
#   - no config -> one is written with check_for_updates false (no upgrade
#     checks, no telemetry) and theme "dark"
#   - a config without the key (e.g. only a theme) gets it added, theme kept
#   - a config without a theme gets "dark", other keys kept
#   - a user's own "check_for_updates": true is left alone
#   - a config that is not JSON is left untouched, and the hook still exits 0
#     (booth-entry runs every hook under set -e)
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/variants/base/setups/fresh--setup.sh"

command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
CONF="$STUB/home/.config/fresh/config.json"
HOOK="$STUB/74-cb-fresh--startup.sh"
mkdir -p "$STUB/home"

fail() { echo "❌ $*"; exit 1; }

# The hook is the STARTUP heredoc in the setup script.
sed -n "/<<'STARTUP'$/,/^STARTUP$/p" "$SETUP" | sed '1d;$d' > "$HOOK"
grep -q 'check_for_updates' "$HOOK" || fail "no startup hook found in $SETUP"

run_hook() { env -i HOME="$STUB/home" PATH="$PATH" bash "$HOOK"; }

# ---- no config: written with updates off and the dark theme ----
run_hook || fail "hook failed"
[[ "$(jq -r '.check_for_updates' "$CONF")" == "false" ]] || fail "fresh config not seeded: $(cat "$CONF")"
[[ "$(jq -r '.theme' "$CONF")" == "dark" ]]           || fail "theme not seeded: $(cat "$CONF")"

# ---- theme-only config: key added, theme kept ----
printf '{"version":1,"theme":"nord"}\n' > "$CONF"
run_hook
[[ "$(jq -r '.check_for_updates' "$CONF")" == "false" ]] || fail "key not added: $(cat "$CONF")"
[[ "$(jq -r '.theme' "$CONF")" == "nord" ]]               || fail "theme lost: $(cat "$CONF")"

# ---- no theme: dark added, other keys kept ----
printf '{"version":1,"check_for_updates":false,"tab_size":2}\n' > "$CONF"
run_hook
[[ "$(jq -r '.theme' "$CONF")" == "dark" ]] || fail "theme not added: $(cat "$CONF")"
[[ "$(jq -r '.tab_size' "$CONF")" == "2" ]] || fail "other key lost: $(cat "$CONF")"

# ---- user opted in: left alone ----
printf '{"version":1,"check_for_updates":true}\n' > "$CONF"
run_hook
[[ "$(jq -r '.check_for_updates' "$CONF")" == "true" ]] || fail "user opt-in overwritten: $(cat "$CONF")"

# ---- not JSON: untouched, and still exit 0 ----
printf 'not json\n' > "$CONF"
run_hook || fail "hook failed on a non-JSON config"
[[ "$(cat "$CONF")" == "not json" ]] || fail "non-JSON config was changed: $(cat "$CONF")"

echo "✅ fresh startup hook seeds the dark theme with updates/telemetry off"
