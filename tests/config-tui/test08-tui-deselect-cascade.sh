#!/bin/bash
# TUI: selecting then deselecting `go` removes it (and its auto-selected
# extension) — the saved config is an empty booth again.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Space once selects go (+vscode-ext); Space again on the same row deselects.
run-tui save \
    'Tab' 'Type "go"' 'Sleep 500ms' \
    'Tab' 'Sleep 300ms' \
    'Space' 'Sleep 400ms' \
    'Space' 'Sleep 400ms'

config="$prj/.booth/config.toml"
boothfile="$prj/.booth/Boothfile"
assert-line "$config" "# Configured by: " "booth config --no-tui --overwrite" "Deselect leaves an empty-booth adjust line"
assert-file-not-contains "$boothfile" "setup go" "Deselected go does not appear in the Boothfile"

finally
