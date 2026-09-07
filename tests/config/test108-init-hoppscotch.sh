#!/bin/bash
# hoppscotch: COPY --from frontend image, port pin, expose, autostart
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: default select
run booth config $prj --no-tui --select "hoppscotch"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg HOPPSCOTCH_VERSION=' '2026.8.0' \
    "default version is 2026.8.0"
assert-line "$boothfile" 'arg HOPPSCOTCH_PORT=' '13000' \
    "default port is 13000"
assert-line "$boothfile" 'copy --from=hoppscotch/hoppscotch-frontend:' '${HOPPSCOTCH_VERSION} /site/selfhost-web /opt/hoppscotch' \
    "Boothfile copies official frontend image"
assert-line "$boothfile" 'setup hoppscotch ' '${HOPPSCOTCH_PORT}' \
    "Boothfile uses HOPPSCOTCH_PORT"

# Test 2: version + port pin
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "hoppscotch:2026.7.0,18000"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg HOPPSCOTCH_VERSION=' '2026.7.0' \
    "custom version is 2026.7.0"
assert-line "$boothfile" 'arg HOPPSCOTCH_PORT=' '18000' \
    "custom port is 18000"

# Test 3: +expose with default port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "hoppscotch+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "13000:13000"]' \
    "expose uses default port 13000"

# Test 4: +expose with custom port — host follows service
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "hoppscotch:2026.8.0,18000+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "18000:18000"]' \
    "expose uses custom port 18000"

# Test 5: +expose:host-port publishes host:service
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "hoppscotch:2026.8.0,18000+expose:19000"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "19000:18000"]' \
    "expose:19000 publishes 19000:18000"

# Test 6: +autostart writes startup with default port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "hoppscotch+autostart"
startup="$prj/.booth/startups/65-hoppscotch-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${HOPPSCOTCH_PORT:-13000}' \
    "startup uses param with default"

# Test 7: version + custom port + expose + autostart
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "hoppscotch:2026.7.0,18000+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-hoppscotch-autostart--startup.sh"
assert-line "$boothfile" 'arg HOPPSCOTCH_VERSION=' '2026.7.0' \
    "full: version pin"
assert-line "$boothfile" 'arg HOPPSCOTCH_PORT=' '18000' \
    "full: custom port"
assert-line "$config"    'run-args = ' '["-p", "18000:18000"]' \
    "full: run-args uses 18000"
assert-line "$startup"   'PORT=' '${HOPPSCOTCH_PORT:-18000}' \
    "full: startup uses param with default 18000"

finally
