#!/bin/bash
# TUI: on the Config tab, edit the Port field and save.
# Down×3 lands on Port; Enter opens the string editor, type a value, Enter commits.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run-tui save \
    'Left' 'Sleep 500ms' \
    'Down' 'Down' 'Down' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms' \
    'Type "9999"' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms'

config="$prj/.booth/config.toml"
assert-line "$config" "port = " '"9999"' "Port field accepts a typed value"

finally
