#!/bin/bash
# TUI: launching with --select pre-checks templates in the TUI.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Launch the TUI pre-populated with `go`; the header should already show the
# go + auto-selected vscode-ext as 2 selected.
LAUNCH_ARGS=(--select go)
run-tui frame 'Sleep 400ms'

assert-frame "[2 selected]" "--select go pre-checks go (+vscode-ext) in the TUI"

finally
