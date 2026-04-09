#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Single --expose with bare port
run booth config $prj --no-tui --select "go" --expose 8080
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "8080:8080"]'  "--expose 8080 produces --publish 8080:8080"

# Test 2: Single --expose with host:container mapping
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose 9090:3000
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "9090:3000"]'  "--expose 9090:3000 used as-is"

# Test 3: Multiple --expose flags
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose 8080 --expose 5432
config="$prj/.booth/config.toml"
assert-line "$config" '    "--publish", "8080:8080",' ''  "first expose in multi run-args"
assert-line "$config" '    "--publish", "5432:5432"'  ''  "second expose in multi run-args"

# Test 4: --expose combined with template run-args
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "openssh+server+expose" --expose 8080
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", "2222:2222",' ''  "template run-args preserved"
assert-line "$config" '    "--publish", "8080:8080"'  ''  "--expose appended after template"

# Test 5: --expose without --select (empty booth)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --expose 3000
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "3000:3000"]'  "--expose works without --select"

# Test 6: adjust command includes --expose
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose 8080
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "# Configured by: " "booth config --no-tui --overwrite --expose 8080 --select go"  "Adjust command includes --expose"

finally
