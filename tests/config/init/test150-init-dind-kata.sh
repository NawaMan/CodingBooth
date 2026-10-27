#!/bin/bash
# Test: the dind+kata extension (experimental) writes dind-isolation and its VM size
#
# dind+kata turns DinD on, asks for the Kata sidecar, and sizes its VM from two runtime
# params: they land in config.toml only, never as Boothfile args, so a new size does
# not rebuild the image. Defaults are read from the catalog, not copied here.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# check <label> <command...>: one numbered result, for what assert-line cannot say (absence).
check() {
    local label="$1"; shift
    TEST_COUNT=$((TEST_COUNT + 1))
    local pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}
absent() { ! grep -q "^$1" "$2"; }

MEM_DEFAULT="$(template-default dind+kata DIND_VM_MEMORY)"
CPUS_DEFAULT="$(template-default dind+kata DIND_VM_CPUS)"

# Test 1-5: defaults
run booth config $prj --no-tui --select "dind+kata"
config="$prj/.booth/config.toml"
boothfile="$prj/.booth/Boothfile"
assert-line "$config" 'dind = ' 'true'                          "dind+kata turns DinD on"
assert-line "$config" 'dind-isolation = ' '"kata"'              "dind+kata asks for the Kata sidecar"
assert-line "$config" 'dind-vm-memory = ' "\"$MEM_DEFAULT\""    "VM memory default is the catalog's"
assert-line "$config" 'dind-vm-cpus = ' "\"$CPUS_DEFAULT\""     "VM CPUs default is the catalog's"
check "VM size is not a Boothfile arg (no rebuild)"            absent 'arg DIND_VM' "$boothfile"

# Test 6-7: a size that is not the default
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "dind+kata:8g,4"
config="$prj/.booth/config.toml"
assert-line "$config" 'dind-vm-memory = ' '"8g"'                "VM memory pin"
assert-line "$config" 'dind-vm-cpus = ' '"4"'                   "VM CPUs pin"

# Test 8: plain dind stays plain
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "dind"
config="$prj/.booth/config.toml"
check "plain dind writes no dind-isolation"                    absent 'dind-isolation' "$config"

finally
