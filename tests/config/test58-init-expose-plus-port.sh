#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: --expose +8080 produces +8080:8080 in run-args
run booth config $prj --no-tui --select "go" --expose +8080
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "+8080:8080"]'  "--expose +8080 produces +8080:8080"

# Test 2: --expose +3000:5000 produces +3000:5000 in run-args
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose +3000:5000
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "+3000:5000"]'  "--expose +3000:5000 kept as-is"

# Test 3: Mixed --expose with plain and +port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose 8080 --expose +3000
config="$prj/.booth/config.toml"
assert-line "$config" '    "--publish", "8080:8080",' ''  "plain 8080 expanded to 8080:8080"
assert-line "$config" '    "--publish", "+3000:3000"' ''  "+3000 expanded to +3000:3000"

# Test 4: --expose +8080 without --select
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --expose +8080
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "+8080:8080"]'  "--expose +8080 works without --select"

# Test 5: adjust command includes +port expose
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose +8080
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "# Configured by: " "booth config --no-tui --overwrite --expose +8080 --select go"  "Adjust command includes +port"

finally
