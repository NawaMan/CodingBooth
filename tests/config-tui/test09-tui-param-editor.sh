#!/bin/bash
# TUI: open a selected template's parameter editor (Enter on the highlighted
# row) and set a custom version value.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Select go, Enter opens the right-pane param editor (GO_VERSION), type a custom
# value, Enter commits it, Esc returns to the list, then save.
run-tui save \
    'Tab' 'Type "go"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 400ms' \
    'Enter' 'Sleep 500ms' \
    'Type "1.24.0"' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms' \
    'Escape' 'Sleep 400ms'

boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg GO_VERSION=" "1.24.0" "Param editor sets a custom GO_VERSION"

finally
