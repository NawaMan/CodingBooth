#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Penpot with defaults — pulls postgresql and redis
run booth config $prj --no-tui --select "penpot"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PENPOT_VERSION=' '2.17.2'  "default image tag is 2.17.2"
assert-line "$boothfile" 'arg PENPOT_PORT=' '19001'  "default port is 19001"
assert-line "$boothfile" 'copy --from=penpotapp/backend:' '${PENPOT_VERSION} /opt/penpot/backend /opt/penpot/backend'  "copies backend image"
assert-line "$boothfile" 'copy --from=penpotapp/frontend:' '${PENPOT_VERSION} /var/www/app /opt/penpot/frontend'  "copies frontend image"
assert-line "$boothfile" 'setup penpot ' '${PENPOT_PORT}'  "Boothfile uses port param"
assert-line "$boothfile" 'setup postgresql ' '--version ${PG_VERSION}'  "requires auto-selects postgresql"
assert-line "$boothfile" 'setup redis ' '--version ${REDIS_VERSION}'  "requires auto-selects redis"

# Test 2: custom image tag and port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "penpot:2.17,18001"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PENPOT_VERSION=' '2.17'  "custom image tag is 2.17"
assert-line "$boothfile" 'arg PENPOT_PORT=' '18001'  "custom port is 18001"

# Test 3: +expose with default port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "penpot+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"19001:19001",'  "expose uses default port 19001"

# Test 4: +expose with custom port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "penpot:2.17.2,18001+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"18001:18001",'  "expose uses custom port 18001"

# Test 5: +autostart writes a startup that calls the starter
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "penpot+autostart"
startup="$prj/.booth/startups/70-penpot-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${PENPOT_PORT:-19001}'  "startup uses param with default"

# Test 6: custom port + expose + autostart stay consistent
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "penpot:2.17.2,18001+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/70-penpot-autostart--startup.sh"
assert-line "$boothfile" 'arg PENPOT_PORT=' '18001'  "full: Boothfile param is 18001"
assert-line "$config"    '    "-p", ' '"18001:18001",'  "full: run-args uses 18001"
assert-line "$startup"   'PORT=' '${PENPOT_PORT:-18001}'  "full: startup uses param with default 18001"

# Test 7: +exporter copies the exporter image and runs its setup
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "penpot+exporter"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'copy --from=penpotapp/exporter:' '${PENPOT_VERSION} /opt/penpot/exporter /opt/penpot/exporter'  "exporter copies official image"
assert-line "$boothfile" 'setup penpot-exporter' ''  "exporter setup is emitted"

finally
