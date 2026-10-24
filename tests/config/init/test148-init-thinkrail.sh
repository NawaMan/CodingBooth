#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# Test 1: ThinkRail defaults come from the catalog
run booth config $prj --no-tui --select "thinkrail"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg THINKRAIL_VERSION=' "$(template-default thinkrail THINKRAIL_VERSION)" "default version is the catalog's"
assert-line "$boothfile" 'arg THINKRAIL_PORT='    "$(template-default thinkrail THINKRAIL_PORT)"    "default port is the catalog's"
assert-line "$boothfile" 'setup thinkrail ' '--version ${THINKRAIL_VERSION} --port ${THINKRAIL_PORT}' "setup passes version and port"

# Test 2: version and port pins land
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "thinkrail:0.1.6,24300"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg THINKRAIL_VERSION=' '0.1.6'  "version pin"
assert-line "$boothfile" 'arg THINKRAIL_PORT='    '24300'  "port pin"

# Test 3: expose + autostart follow the port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "thinkrail:latest,24300+autostart+expose"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-thinkrail-autostart--startup.sh"
assert-line "$config"  'run-args = ' '["-p", "24300:24300"]'         "expose publishes the service port"
assert-line "$startup" 'PORT='      '${THINKRAIL_PORT:-24300}'      "autostart uses the port param"
assert-line "$startup" 'nohup '     'start-thinkrail "$PORT" > "$LOG_FILE" 2>&1 &' "autostart runs the starter"

# Test 4: a different host port moves only the host side
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "thinkrail+expose:34242"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' "[\"-p\", \"34242:$(template-default thinkrail THINKRAIL_PORT)\"]" "expose host-port override"

finally
