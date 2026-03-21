#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: no-sudo sets sudo=false in config.toml
run booth init new $prj --select "no-sudo"
config="$prj/.booth/config.toml"
assert-line "$config" 'sudo = ' 'false'  "config.toml has sudo = false"

# Test 2: no-sudo combined with other templates
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go/no-sudo"
config="$prj/.booth/config.toml"
boothfile="$prj/.booth/Boothfile"
assert-line "$config"    'sudo = ' 'false'  "combined: config.toml has sudo = false"
assert-line "$boothfile" 'setup go '  '${GO_VERSION}                                # GO tool chain'  "combined: go setup present"

finally
