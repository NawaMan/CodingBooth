#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Logo with default port (no extensions)
run booth config $prj --no-tui --select "logo"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg LOGO_PORT=' '18610'  "default port param is 18610"
assert-line "$boothfile" 'setup logo ' '${LOGO_PORT}'  "Boothfile uses param reference"

# Test 2: Logo with custom port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "logo:18700"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg LOGO_PORT=' '18700'  "custom port param is 18700"

# Test 3: Logo+expose with default port — run-args expanded
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "logo+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"18610:18610",'  "expose uses default port 18610"

# Test 4: Logo+expose with custom port — run-args expanded
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "logo:18700+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"18700:18700",'  "expose uses custom port 18700"

# Test 5: Logo+autostart with default port — startup in startups/
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "logo+autostart"
startup="$prj/.booth/startups/65-logo-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${LOGO_PORT:-18610}'  "startup uses param with default"

# Test 6: Logo+expose+autostart with custom port — all consistent
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "logo:18700+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-logo-autostart--startup.sh"
assert-line "$boothfile" 'arg LOGO_PORT=' '18700'  "full: Boothfile param is 18700"
assert-line "$config"    '    "-p", ' '"18700:18700",'  "full: run-args uses 18700"
assert-line "$startup"   'PORT=' '${LOGO_PORT:-18700}'  "full: startup uses param with default 18700"

finally
