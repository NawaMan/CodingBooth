#!/bin/bash
# A template gives Cache and Shared paths their initial content with
# [files.cache-seed] / [files.shared-seed]. booth config writes the seeds to the
# committed .booth/cache-seed/ and .booth/shared-seed/ and fills the paths they cover;
# a later start re-seeds a path that is missing again, as on a fresh clone, where
# .booth/cache/ is not in git. Uses no Docker: a --no-tui write, then a --dryrun run.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

mkdir -p "$prj/.booth/templates"
cat > "$prj/.booth/templates/seeded.toml" <<'TOML'
cache-files  = ["home/coder/.tool/state.json", "home/coder/.tool_history"]
shared-files = ["home/coder/.config/tool/settings.json"]

[files.cache-seed]
"home/coder/.tool/state.json" = '{"state": 0}'

[files.shared-seed]
"home/coder/.config/tool/settings.json" = '{"team": true}'
TOML

# --- The dry run lists both seed folders ---
booth config "$prj" --no-tui --dryrun --select seeded >"$prj/dry.txt" 2>&1 || true
assert-line "$prj/dry.txt" "=== cache-seed/" " ===" "--dryrun lists cache-seed/"
assert-line "$prj/dry.txt" "=== shared-seed/" " ===" "--dryrun lists shared-seed/"

# --- The write lands the seeds and fills the paths ---
run booth config "$prj" --no-tui --overwrite --select seeded
B="$prj/.booth"
assert-line "$B/shared-seed/home/coder/.config/tool/settings.json" '{"team"' ': true}' "shared-seed/ holds the template's seed"
assert-line "$B/shared/home/coder/.config/tool/settings.json" '{"team"' ': true}' "the Shared path starts with the seed"
assert-line "$B/cache-seed/home/coder/.tool/state.json" '{"state"' ': 0}' "cache-seed/ holds the template's seed"
assert-line "$B/cache/home/coder/.tool/state.json" '{"state"' ': 0}' "the Cache path starts with the seed"
wc -c <"$B/cache/home/coder/.tool_history" | tr -d ' ' >"$prj/history-size.txt"
assert-line "$prj/history-size.txt" "0" "" "a Cache path with no seed is created empty"

# --- A user's edit survives a reconfigure ---
echo '{"team": false}' >"$B/shared/home/coder/.config/tool/settings.json"
run booth config "$prj" --no-tui --overwrite --select seeded
assert-line "$B/shared/home/coder/.config/tool/settings.json" '{"team"' ': false}' "reconfigure keeps the edited Shared file"

# --- A fresh clone has no .booth/cache/; the start seeds it again ---
rm -rf "$B/cache"
(cd "$prj" && booth run --dryrun -- true) >"$prj/run.txt" 2>&1 || true
assert-line "$B/cache/home/coder/.tool/state.json" '{"state"' ': 0}' "a start re-seeds a missing Cache path"
assert-line "$prj/run.txt" "Seeded .booth/cache/home/coder/.tool/state.json" " from .booth/cache-seed/" "the start says what it seeded"

finally
