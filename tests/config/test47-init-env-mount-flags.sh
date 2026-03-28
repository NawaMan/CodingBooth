#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Single --env with KEY=VALUE
run booth init new $prj --select "go" --env MY_VAR=hello
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-e", "MY_VAR=hello"]'  "--env MY_VAR=hello produces -e"

# Test 2: Multiple --env flags
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --env FOO=bar --env BAZ=qux
config="$prj/.booth/config.toml"
assert-line "$config" '    "-e", "FOO=bar",' ''  "first env in multi run-args"
assert-line "$config" '    "-e", "BAZ=qux"'  ''  "second env in multi run-args"

# Test 3: Single --mount with host:container
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --mount /data:/app/data
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-v", "/data:/app/data"]'  "--mount produces -v"

# Test 4: --mount with options (ro)
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --mount /data:/app/data:ro
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-v", "/data:/app/data:ro"]'  "--mount with :ro"

# Test 5: Multiple --mount flags
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --mount /data:/app/data --mount /logs:/var/log
config="$prj/.booth/config.toml"
assert-line "$config" '    "-v", "/data:/app/data",' ''  "first mount in multi run-args"
assert-line "$config" '    "-v", "/logs:/var/log"'  ''  "second mount in multi run-args"

# Test 6: --expose + --env + --mount combined
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --expose 8080 --env FOO=bar --mount /tmp:/tmp
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", "8080:8080",' ''  "combined: expose present"
assert-line "$config" '    "-e", "FOO=bar",'   ''  "combined: env present"
assert-line "$config" '    "-v", "/tmp:/tmp"'   ''  "combined: mount present"

# Test 7: --env without --select (empty booth)
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --env DB_HOST=localhost
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-e", "DB_HOST=localhost"]'  "--env works without --select"

# Test 8: --mount without --select (empty booth)
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --mount /data:/data
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-v", "/data:/data"]'  "--mount works without --select"

# Test 9: adjust command includes --env and --mount
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "go" --env FOO=bar --mount /data:/data
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "# Configured by: " "booth init adjust --env FOO=bar --mount /data:/data --select go"  "Adjust command includes --env and --mount"

finally
