#!/bin/bash
# TUI: opening config on a project that already has a .booth/ loads the existing
# selection; adding another template and saving keeps both.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Seed an existing booth (non-interactively) with go already selected.
run() { "$@" >> "$log" 2>&1 ; }
echo "=== seed existing .booth via --no-tui ===" >> "$log"
run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH"

if [[ ! -f "$prj/.booth/Boothfile" ]]; then
    skip "seed step did not produce a .booth/Boothfile"
fi

# Re-open the TUI (loads existing go), add python, save.
run-tui save \
    'Tab' 'Type "python"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 500ms'

boothfile="$prj/.booth/Boothfile"
assert-file-contains "$boothfile" "setup go"     "Existing go selection is preserved"
assert-file-contains "$boothfile" "setup python" "Newly added python is included"

finally
