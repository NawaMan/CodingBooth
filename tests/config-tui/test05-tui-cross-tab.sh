#!/bin/bash
# TUI: select across two tabs — `go` (Languages) and `postgresql` (Databases).
# Exercises clearing the search and switching tabs with the arrow keys.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run-tui save \
    'Tab' 'Type "go"' 'Sleep 500ms' 'Tab' 'Sleep 200ms' 'Space' 'Sleep 400ms' \
    'Tab' 'Escape' 'Sleep 300ms' \
    'Right' 'Sleep 400ms' \
    'Tab' 'Type "postgres"' 'Sleep 500ms' 'Tab' 'Sleep 200ms' 'Space' 'Sleep 400ms'

boothfile="$prj/.booth/Boothfile"
assert-file-contains "$boothfile" "setup go"         "go selected from Languages tab"
assert-file-contains "$boothfile" "setup postgresql" "postgresql selected from Databases tab"

finally
