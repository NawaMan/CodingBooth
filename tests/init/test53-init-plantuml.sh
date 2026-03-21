#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: PlantUML with default params
run booth init new $prj --select "plantuml"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PLANTUML_VERSION=' '1.2025.2'  "default version is 1.2025.2"
assert-line "$boothfile" 'arg PLANTUML_PORT=' '18080'  "default port is 18080"
assert-line "$boothfile" 'setup plantuml ' '${PLANTUML_VERSION} ${PLANTUML_PORT}'  "Boothfile uses param references"

# Test 2: PlantUML with custom version and port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "plantuml:1.2024.8,19090"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PLANTUML_VERSION=' '1.2024.8'  "custom version is 1.2024.8"
assert-line "$boothfile" 'arg PLANTUML_PORT=' '19090'  "custom port is 19090"

# Test 3: PlantUML+expose with default port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "plantuml+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "18080:18080"]'  "expose uses default port 18080"

# Test 4: PlantUML+expose with custom port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "plantuml:1.2025.2,19090+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "19090:19090"]'  "expose uses custom port 19090"

# Test 5: PlantUML+autostart with default port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "plantuml+autostart"
startup="$prj/.booth/startups/65-plantuml-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${PLANTUML_PORT:-18080}'  "startup uses param with default"

# Test 6: PlantUML+expose+autostart with custom port
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "plantuml:1.2025.2,19090+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-plantuml-autostart--startup.sh"
assert-line "$boothfile" 'arg PLANTUML_PORT=' '19090'  "full: Boothfile param is 19090"
assert-line "$config"    'run-args = ' '["-p", "19090:19090"]'  "full: run-args uses 19090"
assert-line "$startup"   'PORT=' '${PLANTUML_PORT:-19090}'  "full: startup uses param with default 19090"

finally
