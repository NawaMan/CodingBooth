#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: build/bump-homebrew-formula.sh
#
# The `Bump Homebrew formula` workflow runs it to point the tap's formula at a release's
# `booth`. A fake release lives under a file:// URL (CB_RELEASE_DOWNLOAD_BASE).
#
# Locked in here:
#   - url and sha256 move to the release; the formula gets the github.com URL,
#     never the download override; livecheck's `url :stable` is untouched
#   - rerunning for the same release prints "unchanged" and changes nothing
#   - a local booth that differs from the published one fails, formula untouched
#   - --rc versions, a missing asset, an asset that is not the wrapper, and a
#     formula with two url lines all fail without editing the formula
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUMP="$REPO_ROOT/build/bump-homebrew-formula.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT

fail() { echo "❌ $*"; exit 1; }

# ---- fake release 0.81.0 ----
mkdir -p "$STUB/rel/0.81.0" "$STUB/rel/0.82.0"
printf '#!/bin/bash\nVERSION=0.17.0\necho wrapper\n' > "$STUB/rel/0.81.0/booth"
printf '<html>Not Found</html>\n'                     > "$STUB/rel/0.82.0/booth"
NEW_SHA=$(sha256sum "$STUB/rel/0.81.0/booth" | awk '{print $1}')
export CB_RELEASE_DOWNLOAD_BASE="file://$STUB/rel"

F="$STUB/codingbooth.rb"
write_formula() {
    cat > "$F" <<'RB'
class Codingbooth < Formula
  desc "Reproducible, containerized dev environments for any project"
  homepage "https://codingbooth.io"
  url "https://github.com/NawaMan/CodingBooth/releases/download/0.80.0/booth"
  sha256 "965458b7c132474692247e82bfe866c2e6e64a78b5b370cde528006963fa7644"
  license "Apache-2.0"

  livecheck do
    url :stable
    strategy :github_releases
  end
end
RB
}

# ---- 1: moves url and sha256 ----
write_formula
out=$("$BUMP" 0.81.0 "$F")
[[ "$(tail -n 1 <<<"$out")" == changed ]] || fail "first run did not say changed: $out"
grep -qx '  url "https://github.com/NawaMan/CodingBooth/releases/download/0.81.0/booth"' "$F" \
    || fail "url not moved to the github.com 0.81.0 URL: $(cat "$F")"
grep -qx "  sha256 \"$NEW_SHA\"" "$F" || fail "sha256 not updated: $(cat "$F")"
grep -qx '    url :stable' "$F"     || fail "livecheck url changed: $(cat "$F")"
grep -q 'file://' "$F"              && fail "download override leaked into the formula"

# ---- 2: rerun is a no-op ----
cp "$F" "$STUB/after1.rb"
out=$("$BUMP" 0.81.0 "$F")
[[ "$(tail -n 1 <<<"$out")" == unchanged ]] || fail "rerun did not say unchanged: $out"
cmp -s "$F" "$STUB/after1.rb" || fail "rerun edited the formula"

# ---- 3: local booth must match the published one ----
write_formula; cp "$F" "$STUB/orig.rb"
printf 'VERSION=other\n' > "$STUB/local-booth"
"$BUMP" 0.81.0 "$F" "$STUB/local-booth" >/dev/null 2>&1 && fail "mismatched local booth accepted"
cmp -s "$F" "$STUB/orig.rb" || fail "formula edited despite the mismatch"
"$BUMP" 0.81.0 "$F" "$STUB/rel/0.81.0/booth" >/dev/null || fail "matching local booth rejected"

# ---- 4: refusals leave the formula alone ----
refuse() {  # <why> <args...>
    local why="$1"; shift
    write_formula
    "$BUMP" "$@" >/dev/null 2>&1 && fail "$why: accepted"
    cmp -s "$F" "$STUB/orig.rb" || fail "$why: formula edited"
}
refuse "--rc version"        0.81.0--rc1 "$F"
refuse "missing asset"       0.83.0      "$F"
refuse "asset is not booth"  0.82.0      "$F"
write_formula; printf '  url "https://example.com/x"\n' >> "$F"; cp "$F" "$STUB/two.rb"
"$BUMP" 0.81.0 "$F" >/dev/null 2>&1 && fail "two url lines accepted"
cmp -s "$F" "$STUB/two.rb" || fail "two url lines: formula edited"

echo "✅ bump-homebrew-formula moves url+sha256 to the release and refuses bad input"
