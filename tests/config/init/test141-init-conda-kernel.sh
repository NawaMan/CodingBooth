#!/bin/bash
# Python +conda-kernel: pulls notebook, emits the conda nb-kernel setup after conda.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

run booth config $prj --no-tui --select "python+conda+conda-pkg:rdkit+conda-kernel"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "setup conda-nb-kernel" "" "conda notebook kernel setup"
assert-line "$boothfile" "setup notebook " '${NOTEBOOK_PORT}' "notebook pulled in by kernel requires"

# The kernel installs ipykernel into the conda env, so it must come after both
# the env (setup conda) and the packages that go into it (install conda).
conda_line=$(grep -nE '^setup conda$' "$boothfile" | cut -d: -f1)
pkgs_line=$(grep -nE '^install conda ' "$boothfile" | cut -d: -f1)
kernel_line=$(grep -nE '^setup conda-nb-kernel$' "$boothfile" | cut -d: -f1)
if [ -z "$conda_line" ] || [ -z "$pkgs_line" ] || [ "$kernel_line" -le "$conda_line" ] || [ "$kernel_line" -le "$pkgs_line" ]; then
    echo "  ❌ setup conda-nb-kernel (line $kernel_line) must follow setup conda ($conda_line) and install conda ($pkgs_line)"
    exit 1
fi

# Bare python+conda does not drag in the kernel (opt-in, like python+kernel).
run booth config $prj --no-tui --overwrite --select "python+conda"
if grep -qE '^setup conda-nb-kernel' "$prj/.booth/Boothfile"; then
    echo "  ❌ a bare 'python+conda' selection pulled in the conda notebook kernel"
    exit 1
fi

finally
