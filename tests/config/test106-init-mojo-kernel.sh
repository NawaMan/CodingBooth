#!/bin/bash
# Mojo +kernel: pulls notebook, emits the nb-kernel setup.
source "$(dirname "$0")/test-helpers--source.sh"

begin

run booth config $prj --no-tui --select "mojo+kernel"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" 'setup mojo --version ${MOJO_VERSION}' "" "mojo setup line"
assert-line "$boothfile" "setup mojo-nb-kernel" "" "mojo notebook kernel setup"
assert-line "$boothfile" "setup notebook " '${NOTEBOOK_PORT}' "notebook pulled in by kernel requires"

if ! grep -qE '^setup python ' "$boothfile"; then
    echo "  ❌ python was not pulled in by mojo requires"
    exit 1
fi

# Bare mojo does not drag in the kernel (opt-in, like python+kernel).
run booth config $prj --no-tui --overwrite --select "mojo"
if grep -qE '^setup mojo-nb-kernel' "$prj/.booth/Boothfile"; then
    echo "  ❌ a bare 'mojo' selection pulled in the notebook kernel"
    exit 1
fi

finally
