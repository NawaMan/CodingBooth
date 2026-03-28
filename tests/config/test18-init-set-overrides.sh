#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: --set with boolean flag (bare key)
run booth init new $prj --select "go" --set dind
configfile="$prj/.booth/config.toml"

assert-line "$configfile" "dind = " "true"  "--set dind writes dind = true"

# Test 2: --set with string value
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --set name=my-booth

configfile="$prj/.booth/config.toml"
assert-line "$configfile" 'name = ' '"my-booth"'  "--set name=my-booth writes name"

# Test 3: --set with boolean false
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --set daemon=false

configfile="$prj/.booth/config.toml"
assert-line "$configfile" "daemon = " "false"  "--set daemon=false writes daemon = false"

# Test 4: --set with multiple values
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --set keep-alive --set dind --set name=test-booth

configfile="$prj/.booth/config.toml"
assert-line "$configfile" "dind = "       "true"           "multiple --set: dind is true"
assert-line "$configfile" "keep-alive = " "true"           "multiple --set: keep-alive is true"
assert-line "$configfile" 'name = '       '"test-booth"'   "multiple --set: name is set"

# Test 5: --set overrides --port (--set has higher precedence)
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --port 3000 --set port=8080

configfile="$prj/.booth/config.toml"
assert-line "$configfile" 'port = ' '"8080"'  "--set port overrides --port flag"

# Test 6: --set coexists with --variant
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --variant base --set keep-alive

configfile="$prj/.booth/config.toml"
assert-line "$configfile" 'variant = '    '"base"'  "--variant still works with --set"
assert-line "$configfile" "keep-alive = " "true"    "--set keep-alive alongside --variant"

# Test 7: adjust command includes --set
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --set dind --set name=test

configfile="$prj/.booth/config.toml"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "# Configured by: " "booth init adjust --set dind --set name=test --select go"  "Adjust command includes --set flags"

finally
