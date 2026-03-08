#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Excalidraw with default port (no extensions)
run booth init new $prj --select "excalidraw"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg EXCALIDRAW_PORT=' '15555'  "default port param is 15555"
assert-line "$boothfile" 'setup excalidraw ' '${EXCALIDRAW_PORT}'  "Boothfile uses param reference"

# Test 2: Excalidraw with custom port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "excalidraw:889"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg EXCALIDRAW_PORT=' '889'  "custom port param is 889"

# Test 3: Excalidraw+expose with default port — run-args expanded
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "excalidraw+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "15555:15555"]'  "expose uses default port 15555"

# Test 4: Excalidraw+expose with custom port — run-args expanded
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "excalidraw:889+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "889:889"]'  "expose uses custom port 889"

# Test 5: Excalidraw+autostart with default port — startup in startups/
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "excalidraw+autostart"
startup="$prj/.booth/startups/65-excalidraw-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${EXCALIDRAW_PORT}'  "startup uses param reference"

# Test 6: Excalidraw+expose+autostart with custom port — all consistent
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "excalidraw:889+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-excalidraw-autostart--startup.sh"
assert-line "$boothfile" 'arg EXCALIDRAW_PORT=' '889'  "full: Boothfile param is 889"
assert-line "$config"    'run-args = ' '["-p", "889:889"]'  "full: run-args uses 889"
assert-line "$startup"   'PORT=' '${EXCALIDRAW_PORT}'  "full: startup uses param reference"

finally
