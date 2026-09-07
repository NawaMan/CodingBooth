#!/bin/bash
# Mojo template: pulls Python, setup line, version pin.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- 1. Mojo pulls Python and emits the setup line --------------------------
run booth config $prj --no-tui --select "mojo"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg MOJO_VERSION=" "1.0.0" "MOJO_VERSION arg"
assert-line "$boothfile" 'setup mojo --version ${MOJO_VERSION}' "" "mojo setup line"

if ! grep -qE '^setup python ' "$boothfile"; then
    echo "  ❌ python was not pulled in by requires"
    exit 1
fi

# --- 2. The version pin lands ----------------------------------------------
run booth config $prj --no-tui --overwrite --select "mojo:1.0.0"
assert-line "$boothfile" "arg MOJO_VERSION=" "1.0.0" "MOJO_VERSION pin stays 1.0.0"

run booth config $prj --no-tui --overwrite --select "mojo:latest"
assert-line "$boothfile" "arg MOJO_VERSION=" "latest" "MOJO_VERSION pin latest"

finally
