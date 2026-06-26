#!/bin/bash
# TUI: launch the config TUI and Ctrl+S with nothing selected.
# Baseline that the VHS harness actually drives the TUI to generation.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run-tui save 'Sleep 200ms'

config="$prj/.booth/config.toml"
assert-file-contains "$config" "# Configured by:" "Empty save generates config.toml"
assert-line "$config" "# Configured by: " "booth config --no-tui --overwrite" "Empty save: no --select in adjust line"

finally
