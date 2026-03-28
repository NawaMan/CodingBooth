#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Mermaid with default params
run booth init new $prj --select "mermaid"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg MERMAID_VERSION=' '11.4.2'  "default version is 11.4.2"
assert-line "$boothfile" 'arg MERMAID_PORT=' '18090'  "default port is 18090"
assert-line "$boothfile" 'setup mermaid ' '${MERMAID_VERSION} ${MERMAID_PORT}'  "Boothfile uses param references"

# Test 2: Mermaid with custom version and port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "mermaid:11.3.0,19190"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg MERMAID_VERSION=' '11.3.0'  "custom version is 11.3.0"
assert-line "$boothfile" 'arg MERMAID_PORT=' '19190'  "custom port is 19190"

# Test 3: Mermaid+expose with default port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "mermaid+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "18090:18090"]'  "expose uses default port 18090"

# Test 4: Mermaid+expose with custom port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "mermaid:11.4.2,19190+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "19190:19190"]'  "expose uses custom port 19190"

# Test 5: Mermaid+autostart with default port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "mermaid+autostart"
startup="$prj/.booth/startups/65-mermaid-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${MERMAID_PORT:-18090}'  "startup uses param with default"

# Test 6: Mermaid+expose+autostart with custom port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "mermaid:11.4.2,19190+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-mermaid-autostart--startup.sh"
assert-line "$boothfile" 'arg MERMAID_PORT=' '19190'  "full: Boothfile param is 19190"
assert-line "$config"    'run-args = ' '["-p", "19190:19190"]'  "full: run-args uses 19190"
assert-line "$startup"   'PORT=' '${MERMAID_PORT:-19190}'  "full: startup uses param with default 19190"

finally
