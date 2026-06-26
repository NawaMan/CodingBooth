#!/bin/bash
# TUI: on the Config tab, cycle the Variant field and save.
# Config field order (top→down): Booth Version, Variant, Port, ...
# So Down×2 lands on Variant; Enter opens cycle-edit, Right advances the value,
# Enter commits. default → base → notebook, so Right×2 selects "notebook".
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run-tui save \
    'Left' 'Sleep 500ms' \
    'Down' 'Down' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms' \
    'Right' 'Sleep 300ms' 'Right' 'Sleep 300ms' \
    'Enter' 'Sleep 400ms'

config="$prj/.booth/config.toml"
assert-line "$config" "variant = " '"notebook"' "Variant field cycles to notebook"

finally
