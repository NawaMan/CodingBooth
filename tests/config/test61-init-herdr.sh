#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Herdr with default params
run booth config $prj --no-tui --select "herdr"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg HERDR_VERSION=' 'latest'  "default version is latest"
assert-line "$boothfile" 'setup herdr ' '--version ${HERDR_VERSION}'  "Boothfile uses param reference"

# Test 2: Herdr with pinned version
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "herdr:0.6.10"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg HERDR_VERSION=' '0.6.10'  "custom version is 0.6.10"

# Test 3: Herdr+autostart switches to single-terminal mode
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "herdr+autostart"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-e", "BOOTH_WEB_SPLIT=false"]'  "autostart disables ttyd split"

# Test 4: Herdr+autostart installs the profile.d launcher via a startup hook
startup="$prj/.booth/startups/80-herdr-autostart--startup.sh"
assert-line "$startup" 'PROFILE=' '/etc/profile.d/99zz-cb-herdr--profile.sh'  "startup writes the profile.d launcher"
assert-line "$startup" 'exec herdr' ''  "launcher hands the terminal to herdr"

finally
