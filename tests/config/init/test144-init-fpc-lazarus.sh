#!/bin/bash
# fpc+lazarus: opt-in extension, setup line after fpc, version default and pin.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

# --- 1. A bare fpc does not pull Lazarus in ---------------------------------
run booth config $prj --no-tui --select "fpc"

if grep -qE '^setup lazarus' "$boothfile"; then
    echo "  ❌ a bare 'fpc' selection pulled in Lazarus (it is opt-in)"
    exit 1
fi

# --- 2. fpc+lazarus emits the setup line with the catalog default -----------
run booth config $prj --no-tui --overwrite --select "fpc+lazarus"

assert-line "$boothfile" "arg LAZARUS_VERSION=" "$(template-default fpc+lazarus LAZARUS_VERSION)" "LAZARUS_VERSION arg"
assert-line "$boothfile" 'setup lazarus --version ${LAZARUS_VERSION}' "" "lazarus setup line"

# Lazarus needs fpc installed first: order 60 after fpc's order 50.
fpc_line=$(grep -n '^setup fpc ' "$boothfile" | cut -d: -f1)
laz_line=$(grep -n '^setup lazarus ' "$boothfile" | cut -d: -f1)
if [[ -z "$fpc_line" || -z "$laz_line" || "$laz_line" -le "$fpc_line" ]]; then
    echo "  ❌ setup lazarus (line $laz_line) must come after setup fpc (line $fpc_line)"
    exit 1
fi

# --- 3. The version pin lands ----------------------------------------------
run booth config $prj --no-tui --overwrite --select "fpc+lazarus:4.4"
assert-line "$boothfile" "arg LAZARUS_VERSION=" "4.4" "LAZARUS_VERSION pin"

finally
