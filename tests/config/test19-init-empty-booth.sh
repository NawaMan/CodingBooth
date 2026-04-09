#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Empty booth (no --select) creates .booth/ with config.toml
run booth config $prj --no-tui

configfile="$prj/.booth/config.toml"
assert-line "$configfile" "# Configured by: " "booth config --no-tui --overwrite"  "Empty booth creates config.toml"

# Test 2: Empty booth with --set values
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --set dind --set name=my-empty

configfile="$prj/.booth/config.toml"
assert-line "$configfile" "dind = "  "true"         "Empty booth --set dind"
assert-line "$configfile" 'name = '  '"my-empty"'   "Empty booth --set name"

# Test 3: Empty booth with --variant and --port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant base --port 8080

configfile="$prj/.booth/config.toml"
assert-line "$configfile" 'variant = ' '"base"'  "Empty booth --variant"
assert-line "$configfile" 'port = '    '"8080"'  "Empty booth --port"

# Test 4: Empty booth adjust command has no --select
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --set keep-alive

configfile="$prj/.booth/config.toml"
assert-line "$configfile" "# Configured by: " "booth config --no-tui --overwrite --set keep-alive"  "Adjust command has no --select"

finally
