#!/bin/bash
# TUI: the fields generated from the config schema round-trip and are editable.
#
# These keys used to have no field at all. Now that they do, they are keys the
# TUI *owns* — a save strips them from the baseline and re-derives them from the
# TUI result — which is a stronger claim than test16's: a pre-population gap no
# longer leaves the value untouched, it deletes it.
#
# The integer keys carry the extra hazard. `idle-time = "30"` fails the TOML
# decode outright, so a save that writes the value back as a string does not
# merely lose a setting, it produces a booth that will not start at all.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run() { "$@" >> "$log" 2>&1 ; }
run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH" \
    --set idle-time=30 \
    --set persist-home \
    --set timezone=Asia/Bangkok \
    --set egress-allowlist=github.com --set egress-allowlist=pypi.org \
    --set project-name=demo
if [[ ! -f "$prj/.booth/config.toml" ]]; then
    skip "seed step did not produce a .booth/config.toml"
fi

config="$prj/.booth/config.toml"

# ── Reopen and save without changing anything ───────────────────────────
run-tui save 'Sleep 500ms'

assert-file-contains "$config" "idle-time = 30"            "int key survives a no-edit save"
assert-file-not-contains "$config" 'idle-time = "30"'      "int key is not re-quoted into an unloadable config"
assert-file-contains "$config" "persist-home = true"       "bool key survives a no-edit save"
assert-file-contains "$config" 'timezone = "Asia/Bangkok"' "string key survives a no-edit save"
assert-file-contains "$config" 'project-name = "demo"'     "project-name survives a no-edit save"
assert-file-contains "$config" '"github.com",'             "list key keeps its first entry"
assert-file-contains "$config" '"pypi.org"'                "list key keeps its second entry"

# The booth must still load. A quoted integer fails the decode, and --dryrun is
# the cheapest way to make booth read config.toml and say so.
dryrun="$prj/dryrun.out"
"$BOOTH_BIN" --code "$prj" --dryrun > "$dryrun" 2>&1 || true
cat "$dryrun" >> "$log"
assert-file-not-contains "$dryrun" "failed to read toml config" \
    "booth reads back the regenerated config.toml"

finally
