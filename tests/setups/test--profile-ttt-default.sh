#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: TTT as the default editor in the base shell profile
#
# Sources the real 99z-cb--profile.sh in an interactive bash with a scratch
# HOME, and asserts:
#   - EDITOR defaults to ttt, and the welcome banner names it
#   - an EDITOR already set (env EDITOR=fresh in a Boothfile) wins
#   - the banner keeps mc as explorer and lists spf and differ
#   - the profile writes no Fresh config: Fresh is no longer in the base, and
#     the fresh template's startup hook seeds it (test--fresh-startup-config.sh)
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILE="$REPO_ROOT/variants/base/99z-cb--profile.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT

fail() { echo "❌ $*"; exit 1; }

run_profile() {
  env -i HOME="$STUB" PATH="$PATH" TERM=dumb "$@" \
    bash --norc --noprofile -i -c "source '$PROFILE'; echo \"EDITOR=\$EDITOR\"" 2>/dev/null
}

# ---- EDITOR and banner say ttt ----
out="$(run_profile)"
grep -q '^EDITOR=ttt$'                       <<<"$out" || fail "EDITOR is not ttt: $out"
grep -q 'editor  *Text editor (ttt)'         <<<"$out" || fail "welcome does not name ttt: $out"
grep -q 'tilde'                              <<<"$out" && fail "welcome still mentions tilde: $out"
grep -q 'explorer  *File manager (mc)'       <<<"$out" || fail "welcome does not name mc as explorer: $out"
grep -qE '^  spf ' <<<"$out"                && fail "welcome still lists spf: $out"
grep -qE '^  lazygit ' <<<"$out"            && fail "welcome still lists lazygit: $out"
grep -qE '^  differ ' <<<"$out"             && fail "welcome still lists differ: $out"
[[ -e "$STUB/.config/fresh" ]]              && fail "profile still writes a Fresh config"

# ---- an EDITOR the booth already set wins ----
out="$(run_profile EDITOR=fresh)"
grep -q '^EDITOR=fresh$' <<<"$out" || fail "a set EDITOR was overridden: $out"

echo "✅ profile makes TTT the default editor"
