#!/bin/bash
# TUI: exiting via Ctrl+E → Enter (confirm) discards changes — no .booth/ is
# written even though a template was selected.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Select go, then Ctrl+E (exit prompt) → Enter (confirm quit without saving).
run-tui raw \
    'Tab' 'Type "go"' 'Sleep 400ms' \
    'Tab' 'Sleep 200ms' 'Space' 'Sleep 400ms' \
    'Ctrl+E' 'Sleep 500ms' 'Enter' 'Sleep 800ms'

assert-file-missing "$prj/.booth" "Quit-without-saving writes no .booth/ directory"

finally
