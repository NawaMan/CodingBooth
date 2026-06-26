#!/bin/bash
# TUI: selecting `go` auto-selects its `*vscode-ext` extension.
# Verified both in the rendered frame (footer notice + selection count) and in
# the generated Boothfile.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Frame check: select go, leave TUI displayed, capture the auto-select notice.
run-tui frame \
    'Tab' 'Type "go"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 600ms'

assert-frame "Auto: go/vscode-ext" "Footer shows auto-selected vscode-ext"
assert-frame "[2 selected]"        "Selecting go counts go + vscode-ext (2)"

# File check: save the same selection and confirm the extension landed.
rm -Rf "$prj"; mkdir -p "$prj"
run-tui save \
    'Tab' 'Type "go"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 500ms'

boothfile="$prj/.booth/Boothfile"
assert-file-contains "$boothfile" "go-code-extension" "vscode-ext compiles into the Boothfile"
assert-file-contains "$boothfile" "vscode-ext"        "Adjust line records the auto-selected extension"

finally
