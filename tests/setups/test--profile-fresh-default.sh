#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: Fresh as the default editor in the base shell profile
#
# Sources the real 99z-cb--profile.sh in an interactive bash with a scratch
# HOME, and asserts:
#   - EDITOR defaults to fresh, and the welcome banner names it
#   - no Fresh config -> one is written with check_for_updates false (no
#     upgrade checks, no telemetry)
#   - a config without the key (e.g. only a theme) gets it added, other keys kept
#   - a user's own "check_for_updates": true is left alone
#   - a config that is not JSON is left untouched
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILE="$REPO_ROOT/variants/base/99z-cb--profile.sh"

command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
CONF="$STUB/.config/fresh/config.json"

fail() { echo "❌ $*"; exit 1; }

run_profile() {
  env -i HOME="$STUB" PATH="$PATH" TERM=dumb \
    bash --norc --noprofile -i -c "source '$PROFILE'; echo \"EDITOR=\$EDITOR\"" 2>/dev/null
}

# ---- no config: written with updates off; EDITOR and banner say fresh ----
out="$(run_profile)"
grep -q '^EDITOR=fresh$'                     <<<"$out" || fail "EDITOR is not fresh: $out"
grep -q 'editor  *Text editor (fresh)'       <<<"$out" || fail "welcome does not name fresh: $out"
grep -q 'tilde'                              <<<"$out" && fail "welcome still mentions tilde: $out"
[[ "$(jq -r '.check_for_updates' "$CONF")" == "false" ]] || fail "fresh config not seeded: $(cat "$CONF")"

# ---- theme-only config: key added, theme kept ----
printf '{"version":1,"theme":"nord"}\n' > "$CONF"
run_profile >/dev/null
[[ "$(jq -r '.check_for_updates' "$CONF")" == "false" ]] || fail "key not added: $(cat "$CONF")"
[[ "$(jq -r '.theme' "$CONF")" == "nord" ]]               || fail "theme lost: $(cat "$CONF")"

# ---- user opted in: left alone ----
printf '{"version":1,"check_for_updates":true}\n' > "$CONF"
run_profile >/dev/null
[[ "$(jq -r '.check_for_updates' "$CONF")" == "true" ]] || fail "user opt-in overwritten: $(cat "$CONF")"

# ---- not JSON: untouched ----
printf 'not json\n' > "$CONF"
run_profile >/dev/null
[[ "$(cat "$CONF")" == "not json" ]] || fail "non-JSON config was changed: $(cat "$CONF")"

echo "✅ profile makes Fresh the default editor with updates/telemetry off"
