#!/bin/bash
# floci template: CLI setup, version pin, autostart (pulls dind), expose.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: default select
run booth config $prj --no-tui --select "floci"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" "arg FLOCI_VERSION=" 'latest'              "default FLOCI_VERSION is latest"
assert-line "$boothfile" "arg FLOCI_PORT=" '4566'                    "default FLOCI_PORT is 4566"
assert-line "$boothfile" "setup floci --version " '${FLOCI_VERSION}' "Boothfile uses FLOCI_VERSION"

# Test 2: version pin
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "floci:0.2.1"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg FLOCI_VERSION=" '0.2.1'  "floci version pin"

# Test 3: expose publishes the default port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "floci+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"4566:4566"'  "expose uses default port 4566"

# Test 4: autostart pulls in dind and writes a startup script
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "floci+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-floci-autostart--startup.sh"
assert-line "$boothfile" "setup dind" ''            "autostart auto-selects dind setup"
assert-line "$config" "dind = " 'true'              "autostart sets dind = true"
assert-line "$startup" 'PORT=' '${FLOCI_PORT:-4566}' "startup uses FLOCI_PORT with default"

# Test 5: version + custom port + expose
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "floci:0.2.1,4567+expose"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" "arg FLOCI_VERSION=" '0.2.1'     "full: version pin"
assert-line "$boothfile" "arg FLOCI_PORT=" '4567'         "full: custom FLOCI_PORT"
assert-line "$config" '    "-p", ' '"4567:4567"'          "full: expose uses custom port"

finally
