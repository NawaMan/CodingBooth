#!/bin/bash
# TUI: search "go" on the Languages tab, select it with Space, save.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Tab→search, type, Tab→back to list (cursor on first match = go), Space, save.
run-tui save \
    'Tab' 'Type "go"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 500ms'

boothfile="$prj/.booth/Boothfile"
assert-file-contains "$boothfile" "setup go" "Selecting go writes 'setup go' to Boothfile"
assert-file-contains "$boothfile" "go" "Adjust line records the go selection"

finally
