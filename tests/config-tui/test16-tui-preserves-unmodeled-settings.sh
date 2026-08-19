#!/bin/bash
# TUI: settings the TUI has no field for must survive a reopen+save.
#
# Saving regenerates config.toml from scratch, so anything the save path does not
# carry forward is deleted from the booth. The TUI renders only a subset of what a
# booth can hold, and the save path used to rebuild the whole file from the TUI
# result alone — so --cmd and every --set key without a field (timezone,
# persist-home, ...) silently vanished on a save that changed nothing.
#
# The second half is the mirror image: a key the TUI *does* render must still be
# removable by unchecking it. A fix that merely kept the whole baseline would pass
# the first assertions and break this one.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Seed a booth holding a mix of settings:
#   - keep-alive  → the TUI renders this one (must be removable below)
#   - timezone / persist-home → --set keys with no TUI field
#   - sudo=false  → tri-state cycle field; empty means "default", which is *enabled*,
#                   so losing it silently turns passwordless sudo back on
#   - --cmd       → cmds array, no TUI field
run() { "$@" >> "$log" 2>&1 ; }
run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH" \
    --cmd "echo hello" \
    --set keep-alive --set timezone=Asia/Bangkok --set persist-home --set sudo=false
if [[ ! -f "$prj/.booth/config.toml" ]]; then
    skip "seed step did not produce a .booth/config.toml"
fi

config="$prj/.booth/config.toml"

# ── Reopen and save without changing anything ───────────────────────────
# The booth is `booth config`'s own output, so there is no drift warning and no
# overwrite confirmation — a plain Ctrl+S writes straight through.
run-tui save 'Sleep 500ms'

assert-file-contains "$config" 'timezone = "Asia/Bangkok"' "timezone survives a no-edit TUI save"
assert-file-contains "$config" "persist-home = true"       "persist-home survives a no-edit TUI save"
assert-file-contains "$config" "sudo = false"              "sudo=false survives a no-edit TUI save"
assert-file-contains "$config" "keep-alive = true"         "keep-alive survives a no-edit TUI save"
assert-file-contains "$config" '"echo",'                   "cmds survives a no-edit TUI save"

# ── Now uncheck a field the TUI *does* render ───────────────────────────
# Config is tab 0 and the TUI opens on Languages, so ◄ first. From the top of the
# config list (Booth Version), eight ▼ reach "Keep Alive":
#   Variant, Port, Offset Base, Name, Version, Docker-in-Docker, Keep Alive is
# the 8th stop after the group headers are skipped. Space unchecks it.
#
# This count tracks the rendered field list: "Offset Base" was added between Port
# and Name, which pushed Keep Alive from the 7th stop to the 8th and left the old
# seven ▼ toggling Docker-in-Docker instead. Adding a config field above Keep
# Alive means bumping this count.
run-tui save 'Left' 'Sleep 300ms' \
    'Down' 'Down' 'Down' 'Down' 'Down' 'Down' 'Down' 'Down' 'Sleep 300ms' \
    'Space' 'Sleep 500ms'

assert-frame "[ ] Keep Alive" "the TUI shows Keep Alive unchecked before saving"
assert-file-not-contains "$config" "keep-alive" "unchecking Keep Alive removes it from config.toml"

# ...and the un-rendered settings are still there afterwards.
assert-file-contains "$config" 'timezone = "Asia/Bangkok"' "timezone survives a save that edits another field"
assert-file-contains "$config" "persist-home = true"       "persist-home survives a save that edits another field"
assert-file-contains "$config" '"echo",'                   "cmds survives a save that edits another field"

finally
